import Cocoa
import os

let log = Logger(subsystem: "com.zmievsa.flick", category: "flick")

/// A row of the Switcher: a window, or a running app with no windows (`wid` is `kCGNullWindowID`), which the
/// Dock still shows. Immutable, so any thread can read it.
struct WindowSnapshot {
    let wid: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
    let app: NSRunningApplication
    let appName: String
    let icon: NSImage?

    var isWindowless: Bool { wid == kCGNullWindowID }
}

private final class TrackedWindow {
    let wid: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    var title: String
    var isMinimized: Bool

    init(_ candidate: Candidate, pid: pid_t) {
        wid = candidate.wid
        self.pid = pid
        element = candidate.element
        title = candidate.title
        isMinimized = candidate.isMinimized
    }
}

/// Icon and name are read once per app; reading them again on every ⌘Tab costs ~2 ms per app.
private struct AppInfo {
    let app: NSRunningApplication
    let name: String
    let icon: NSImage?

    var windowlessRow: WindowSnapshot {
        WindowSnapshot(wid: kCGNullWindowID, pid: app.processIdentifier, element: AXUIElementCreateApplication(app.processIdentifier),
                       title: "", isMinimized: false, app: app, appName: name, icon: icon)
    }
}

/// A window found off the main thread, with its attributes already read.
private struct Candidate {
    let wid: CGWindowID
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
}

private let appNotifications = [
    kAXWindowCreatedNotification,
    kAXFocusedWindowChangedNotification,
    kAXMainWindowChangedNotification,
]

private let windowNotifications = [
    kAXUIElementDestroyedNotification,
    kAXTitleChangedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
]

private let observerCallback: AXObserverCallback = { _, element, notification, _ in
    WindowTracker.shared.handle(element, notification as String)
}

/// Keeps every window of every app in Recency order. State lives on the main thread; the Switcher reads
/// the published snapshot from its own thread.
final class WindowTracker {
    static let shared = WindowTracker()

    private var windows: [CGWindowID: TrackedWindow] = [:]
    private var recency: [CGWindowID] = []
    private var observers: [pid_t: AXObserver] = [:]
    /// Every app Flick watches, including ones that never answer Accessibility.
    private var apps: [pid_t: AppInfo] = [:]
    /// Apps by when they were last in front, most recent first.
    private var appRecency: [pid_t] = []
    private var rejected: Set<CGWindowID> = []
    /// Apps Flick is still waiting on to answer Accessibility.
    private var registering: Set<pid_t> = []
    private let selfPID = getpid()
    private let discovery = DispatchQueue(label: "flick.discovery", qos: .userInitiated, attributes: .concurrent)

    private let lock = NSLock()
    private var published: [WindowSnapshot] = []
    private var publishedApps: [AppInfo] = []

    private var dumpSignal: DispatchSourceSignal?

    func start() {
        // `pkill -USR1 Flick` logs what Flick tracks, for debugging missing windows. main.swift ignores the
        // signal from launch, so one sent before this point doesn't kill Flick.
        dumpSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        dumpSignal?.setEventHandler { [weak self] in self?.dump() }
        dumpSignal?.resume()
        recency = Self.cgWindows(onScreenOnly: true).map(\.wid)
        for app in NSWorkspace.shared.runningApplications { watch(app) }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.watch(app)
            }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.forget(pid: app.processIdentifier)
            }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.frontAppChanged(app)
            }
        }
        NotificationCenter.default.addObserver(forName: .residentsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.publish()
        }
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            if let app = NSWorkspace.shared.frontmostApplication { self?.frontAppChanged(app) }
        }
    }

    // MARK: - Reading (any thread)

    /// Windows in Recency order, minus any the WindowServer no longer has and any the app ordered out, then
    /// the Dock's apps that have no windows left, most recently used first, minus Resident apps.
    func snapshot() -> [WindowSnapshot] {
        lock.lock()
        var list = published
        let apps = publishedApps
        lock.unlock()
        if !list.isEmpty, let onScreen = Self.onScreenStates(list.map(\.wid)) {
            let dead = Set(list.map(\.wid)).filter { onScreen[$0] == nil }
            if !dead.isEmpty {
                DispatchQueue.main.async { for wid in dead { self.remove(wid) } }
            }
            // Ordered-out windows stay tracked so they come back if the app shows them again.
            list.removeAll { dead.contains($0.wid) || Self.isOrderedOut($0, onScreen: onScreen[$0.wid] == true) }
        }
        let withWindows = Set(list.map(\.pid))
        // Policy is read now: apps like OrbStack show in the Dock only while one of their windows is open.
        list += apps.filter {
            $0.app.activationPolicy == .regular && !$0.app.isTerminated && !withWindows.contains($0.app.processIdentifier)
        }.map(\.windowlessRow)
        return list
    }

    /// AltTab's phantom rule: a window that belongs to a visible Space but isn't on screen, without being
    /// minimized or hidden with its app, was closed by an app that keeps it around (Shottr, Electron
    /// `show: false`). Other-Space windows are off screen too, but their Space isn't visible.
    private static func isOrderedOut(_ window: WindowSnapshot, onScreen: Bool) -> Bool {
        guard !onScreen, !window.isMinimized, !window.app.isHidden else { return false }
        return isOnVisibleSpace(window.wid)
    }

    /// Moves a window to the front of the Recency order right away, so the next ⌘Tab already sees it.
    func promote(_ wid: CGWindowID) {
        lock.lock()
        if let index = published.firstIndex(where: { $0.wid == wid }) {
            published.insert(published.remove(at: index), at: 0)
        }
        lock.unlock()
        DispatchQueue.main.async { self.promoteOnMain(wid) }
    }

    private func promoteOnMain(_ wid: CGWindowID) {
        guard windows[wid] != nil else { return }
        recency.removeAll { $0 == wid }
        recency.insert(wid, at: 0)
        publish()
    }

    private func publish() {
        let list = recency.compactMap { wid -> WindowSnapshot? in
            guard let window = windows[wid], let info = apps[window.pid] else { return nil }
            return WindowSnapshot(wid: wid, pid: window.pid, element: window.element, title: window.title,
                                  isMinimized: window.isMinimized, app: info.app, appName: info.name, icon: info.icon)
        }
        let appList = appRecency.compactMap { apps[$0] }.filter { !Residents.shared.contains($0.app) }
        lock.lock()
        published = list
        publishedApps = appList
        lock.unlock()
    }

    private func dump() {
        for (pid, info) in apps.sorted(by: { $0.value.name < $1.value.name }) where observers[pid] != nil {
            let tracked = windows.values.filter { $0.pid == pid }.count
            log.notice("dump \(info.name, privacy: .public) pid \(pid, privacy: .public): \(tracked, privacy: .public) windows")
        }
        let shown = snapshot().map { $0.isWindowless ? "\($0.appName) (no windows)" : "\($0.appName): \($0.title)" }
            .joined(separator: " | ")
        log.notice("dump shown \(shown, privacy: .public)")
        log.notice("dump total \(self.windows.count, privacy: .public), published \(self.published.count, privacy: .public), recency \(self.recency.count, privacy: .public), rejected \(self.rejected.count, privacy: .public)")
    }

    // MARK: - Apps

    /// Starts observing an app. Apps answer Accessibility only after a moment, and at login, with every app
    /// starting at once, that moment can stretch past a minute, so Flick keeps asking for two minutes.
    /// Activating the app asks again after that.
    private func watch(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, attempt > 0 || !registering.contains(pid), pid != selfPID, !app.isTerminated,
              !Rules.isExcluded(app), app.activationPolicy != .prohibited else { return }
        if apps[pid] == nil {
            // Known before it answers Accessibility, so a frozen app still gets a row you can quit it from.
            apps[pid] = AppInfo(app: app, name: app.localizedName ?? "", icon: app.icon)
            appRecency.append(pid)
            publish()
        }
        registering.insert(pid)
        // Off the main thread: an app that doesn't answer holds each call for the full messaging timeout.
        discovery.async {
            let observer = Self.observe(pid)
            DispatchQueue.main.async {
                guard let observer else {
                    guard attempt < 30, !app.isTerminated else {
                        self.registering.remove(pid)
                        if !app.isTerminated { log.notice("\(app.localizedName ?? "", privacy: .public) never answered Accessibility; activating it will try again") }
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + min(0.5 * Double(attempt + 1), 5)) {
                        self.watch(app, attempt: attempt + 1)
                    }
                    return
                }
                self.registering.remove(pid)
                guard self.observers[pid] == nil, !app.isTerminated else { return }
                self.started(app, observer)
            }
        }
    }

    /// An observer for the app's window notifications, or nil while the app doesn't answer.
    private static func observe(_ pid: pid_t) -> AXObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, observerCallback, &observer) == .success, let observer else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var ready = false
        for name in appNotifications {
            let result = AXObserverAddNotification(observer, appElement, name as CFString, nil)
            if result == .success || result == .notificationAlreadyRegistered { ready = true }
        }
        return ready ? observer : nil
    }

    private func started(_ app: NSRunningApplication, _ observer: AXObserver) {
        let pid = app.processIdentifier
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        discover(pid: pid, bruteForce: true)
        // An app that is still starting answers before it has shown Accessibility all its windows, and never
        // announces the ones that already exist. At login that left windows missing until you clicked the app.
        for delay in [1.0, 2, 4, 8, 16, 32, 64] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.observers[pid] === observer else { return }
                self.discover(pid: pid, bruteForce: true, retryRejected: true)
            }
        }
        // A launching app usually comes to the front before it answers Accessibility, so frontAppChanged
        // skipped it and its windows would land at the end of the Recency order.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { promoteFocusedWindow(of: pid) }
    }

    private func forget(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        apps[pid] = nil
        appRecency.removeAll { $0 == pid }
        registering.remove(pid) // Its retries stop on their own, and a new app may reuse the pid.
        for (wid, window) in windows where window.pid == pid { remove(wid) }
        publish()
    }

    private func frontAppChanged(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        if observers[pid] == nil { watch(app) }
        if let index = appRecency.firstIndex(of: pid), index > 0 {
            appRecency.insert(appRecency.remove(at: index), at: 0)
            publish()
        }
        guard observers[pid] != nil else { return }
        promoteFocusedWindow(of: pid)
        discover(pid: pid, bruteForce: false)
    }

    private func promoteFocusedWindow(of pid: pid_t) {
        discovery.async {
            let appElement = AXUIElementCreateApplication(pid)
            let focused = appElement.element(kAXFocusedWindowAttribute).flatMap(Self.candidate)
            DispatchQueue.main.async {
                guard let focused else { return }
                self.adopt(focused, pid: pid)
                self.promoteOnMain(focused.wid)
            }
        }
    }

    /// Finds the app's windows: the ones Accessibility lists, plus, when asked, other-Space windows the
    /// WindowServer knows about but Accessibility hides. `retryRejected` looks again at windows that weren't
    /// switchable last time, which an app that was still starting may have misreported.
    private func discover(pid: pid_t, bruteForce: Bool, retryRejected: Bool = false) {
        let tracked = Set(windows.values.filter { $0.pid == pid }.map(\.wid))
        let known = retryRejected ? tracked : tracked.union(rejected)
        discovery.async {
            let appElement = AXUIElementCreateApplication(pid)
            var candidates = appElement.elements(kAXWindowsAttribute).compactMap(Self.candidate)
            var missing = Set<CGWindowID>()
            if bruteForce {
                let seen = Set(candidates.map(\.wid)).union(known)
                missing = Set(Self.allWindowsCached().filter { $0.pid == pid && !seen.contains($0.wid) }.map(\.wid))
                candidates += AXUIElement.windowsByBruteForce(pid: pid, wids: missing).compactMap(Self.candidate)
            }
            let accepted = Set(candidates.map(\.wid))
            DispatchQueue.main.async {
                for candidate in candidates { self.adopt(candidate, pid: pid) }
                self.rejected.formUnion(missing.subtracting(accepted))
                self.publish()
            }
        }
    }

    // MARK: - Windows

    /// Reads a window's attributes. Nil for anything you wouldn't switch to. Same admission rule as AltTab's
    /// WindowAdmissionResolver: standard windows, titled dialogs (Mail's viewer is one), and the app's main window.
    private static func candidate(_ element: AXUIElement) -> Candidate? {
        guard let wid = element.windowID, element.string(kAXRoleAttribute) == kAXWindowRole else { return nil }
        let subrole = element.string(kAXSubroleAttribute)
        let title = element.string(kAXTitleAttribute) ?? ""
        let admitted = subrole == kAXStandardWindowSubrole
            || (subrole == kAXDialogSubrole && !title.isEmpty)
            || (subrole != kAXFloatingWindowSubrole && subrole != "AXSystemDialog" && element.bool(kAXMainAttribute) == true)
        guard admitted, isNormalLayer(wid) else { return nil }
        return Candidate(wid: wid, element: element, title: title, isMinimized: element.bool(kAXMinimizedAttribute) ?? false)
    }

    private func adopt(_ candidate: Candidate, pid: pid_t) {
        guard windows[candidate.wid] == nil, let observer = observers[pid] else { return }
        windows[candidate.wid] = TrackedWindow(candidate, pid: pid)
        rejected.remove(candidate.wid)
        if !recency.contains(candidate.wid) { recency.append(candidate.wid) }
        for name in windowNotifications {
            AXObserverAddNotification(observer, candidate.element, name as CFString, nil)
        }
        publish()
    }

    private func remove(_ wid: CGWindowID) {
        guard let window = windows.removeValue(forKey: wid) else { return }
        recency.removeAll { $0 == wid }
        if let observer = observers[window.pid] {
            for name in windowNotifications {
                AXObserverRemoveNotification(observer, window.element, name as CFString)
            }
        }
        publish()
    }

    private func window(for element: AXUIElement) -> TrackedWindow? {
        if let wid = element.windowID, let window = windows[wid] { return window }
        return windows.values.first { CFEqual($0.element, element) }
    }

    fileprivate func handle(_ element: AXUIElement, _ notification: String) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            if let window = window(for: element) { remove(window.wid) }
        case kAXTitleChangedNotification:
            guard let window = window(for: element) else { return }
            discovery.async {
                guard let title = element.string(kAXTitleAttribute) else { return }
                DispatchQueue.main.async {
                    window.title = title
                    self.publish()
                }
            }
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            window(for: element)?.isMinimized = notification == kAXWindowMiniaturizedNotification
            publish()
        case kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            guard let pid = element.pid else { return }
            let isFocus = notification != kAXWindowCreatedNotification
            discovery.async {
                // A new window can report its subrole a moment late.
                var candidate = Self.candidate(element)
                if candidate == nil, !isFocus {
                    Thread.sleep(forTimeInterval: 0.3)
                    candidate = Self.candidate(element)
                }
                DispatchQueue.main.async {
                    guard let candidate else { return }
                    self.adopt(candidate, pid: pid)
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { self.promoteOnMain(candidate.wid) }
                }
            }
        default:
            break
        }
    }

    // MARK: - WindowServer

    struct CGWindow {
        let wid: CGWindowID
        let pid: pid_t
        let bounds: CGRect
    }

    /// Popups and helper surfaces sit above layer 0 even when they call themselves dialogs (Google Drive does).
    private static func isNormalLayer(_ wid: CGWindowID) -> Bool {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]])?.first else { return false }
        return (info[kCGWindowLayer as String] as? Int) == 0
    }

    /// Whether each window is on screen, keyed by ID; windows the WindowServer no longer has are missing.
    /// Asks only about the given windows (~0.4 ms), because listing all of them takes ~90 ms when a system
    /// service leaks thousands (seen: 13,000 from CursorUIViewService).
    static func onScreenStates(_ wids: [CGWindowID]) -> [CGWindowID: Bool]? {
        // This call wants the IDs themselves as the array's values, not CFNumbers.
        var values = wids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let ids = CFArrayCreate(nil, &values, values.count, nil),
              let list = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]] else { return nil }
        var states: [CGWindowID: Bool] = [:]
        for info in list {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            states[wid] = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        }
        return states
    }

    private static func isOnVisibleSpace(_ wid: CGWindowID) -> Bool {
        let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), kCGSSpaceVisible, [wid] as CFArray)?.takeRetainedValue()
        return (spaces as? [Any])?.isEmpty == false
    }

    private static let cacheLock = NSLock()
    private static var cachedAll: (at: Date, windows: [CGWindow])?

    /// All-Space window details are slow (~90 ms), so app discovery shares one reading for 2 seconds.
    private static func allWindowsCached() -> [CGWindow] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedAll, Date().timeIntervalSince(cachedAll.at) < 2 { return cachedAll.windows }
        let windows = cgWindows(onScreenOnly: false)
        cachedAll = (Date(), windows)
        return windows
    }

    /// Normal-layer windows, front to back. `onScreenOnly` limits it to the current Space.
    static func cgWindows(onScreenOnly: Bool) -> [CGWindow] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 50, bounds.height >= 50 else { return nil }
            return CGWindow(wid: wid, pid: pid, bounds: bounds)
        }
    }
}
