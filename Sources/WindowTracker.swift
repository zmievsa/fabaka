import Cocoa
import os

let log = Logger(subsystem: "com.zmievsa.flick", category: "flick")

/// A window as the Switcher sees it. Immutable, so any thread can read it.
struct WindowSnapshot {
    let wid: CGWindowID
    let pid: pid_t
    let element: AXUIElement
    let title: String
    let isMinimized: Bool
    let app: NSRunningApplication
    let appName: String
    let icon: NSImage?
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

/// Lists every window ID the WindowServer has. IDs only: asking for window details instead takes ~90 ms
/// when a system service leaks thousands of windows (seen: 13,000 from CursorUIViewService).
@_silgen_name("CGWindowListCreate")
private func cgWindowListCreate(_ option: UInt32, _ relativeTo: CGWindowID) -> Unmanaged<CFArray>?

/// Keeps every window of every app in Recency order. State lives on the main thread; the Switcher reads
/// the published snapshot from its own thread.
final class WindowTracker {
    static let shared = WindowTracker()

    private var windows: [CGWindowID: TrackedWindow] = [:]
    private var recency: [CGWindowID] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var apps: [pid_t: AppInfo] = [:]
    private var rejected: Set<CGWindowID> = []
    private let selfPID = getpid()
    private let discovery = DispatchQueue(label: "flick.discovery", qos: .userInitiated, attributes: .concurrent)

    private let lock = NSLock()
    private var published: [WindowSnapshot] = []

    func start() {
        recency = Self.cgWindows(onScreenOnly: true).map(\.wid)
        for app in NSWorkspace.shared.runningApplications { watch(app, attempt: 0) }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.watch(app, attempt: 0)
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
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            if let app = NSWorkspace.shared.frontmostApplication { self?.frontAppChanged(app) }
        }
    }

    // MARK: - Reading (any thread)

    /// Windows in Recency order, minus any the WindowServer no longer has. Takes ~3 ms.
    func snapshot() -> [WindowSnapshot] {
        lock.lock()
        var list = published
        lock.unlock()
        guard let ids = cgWindowListCreate(CGWindowListOption.optionAll.rawValue, kCGNullWindowID)?.takeRetainedValue() else { return list }
        var ours = Set(list.map(\.wid))
        var live = Set<CGWindowID>()
        for i in 0..<CFArrayGetCount(ids) {
            let wid = CGWindowID(UInt(bitPattern: CFArrayGetValueAtIndex(ids, i)))
            if ours.remove(wid) != nil { live.insert(wid) }
            if ours.isEmpty { break }
        }
        let dead = Set(list.map(\.wid)).subtracting(live)
        if !dead.isEmpty {
            list.removeAll { dead.contains($0.wid) }
            DispatchQueue.main.async { for wid in dead { self.remove(wid) } }
        }
        return list
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
        lock.lock()
        published = list
        lock.unlock()
    }

    // MARK: - Apps

    private func watch(_ app: NSRunningApplication, attempt: Int) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, pid != selfPID, !app.isTerminated, !Rules.isExcluded(app),
              app.activationPolicy != .prohibited else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, observerCallback, &observer) == .success, let observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        var ready = false
        for name in appNotifications {
            let result = AXObserverAddNotification(observer, appElement, name as CFString, nil)
            if result == .success || result == .notificationAlreadyRegistered { ready = true }
        }
        guard ready else {
            // Freshly launched apps answer Accessibility only after a moment.
            if attempt < 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * Double(attempt + 1)) { [weak self] in
                    self?.watch(app, attempt: attempt + 1)
                }
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        apps[pid] = AppInfo(app: app, name: app.localizedName ?? "", icon: app.icon)
        discover(pid: pid, bruteForce: true)
    }

    private func forget(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        apps[pid] = nil
        for (wid, window) in windows where window.pid == pid { remove(wid) }
        publish()
    }

    private func frontAppChanged(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] != nil else { return }
        discovery.async {
            let appElement = AXUIElementCreateApplication(pid)
            let focused = appElement.element(kAXFocusedWindowAttribute).flatMap(Self.candidate)
            DispatchQueue.main.async {
                guard let focused else { return }
                self.adopt(focused, pid: pid)
                self.promoteOnMain(focused.wid)
            }
        }
        discover(pid: pid, bruteForce: false)
    }

    /// Finds the app's windows: the ones Accessibility lists, plus, when asked, other-Space windows the
    /// WindowServer knows about but Accessibility hides.
    private func discover(pid: pid_t, bruteForce: Bool) {
        let known = Set(windows.values.filter { $0.pid == pid }.map(\.wid)).union(rejected)
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

    /// Reads a window's attributes. Nil for anything that isn't a normal window.
    private static func candidate(_ element: AXUIElement) -> Candidate? {
        guard let wid = element.windowID,
              element.string(kAXRoleAttribute) == kAXWindowRole,
              element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { return nil }
        return Candidate(wid: wid, element: element, title: element.string(kAXTitleAttribute) ?? "",
                         isMinimized: element.bool(kAXMinimizedAttribute) ?? false)
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
