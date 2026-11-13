import Cocoa
import Carbon.HIToolbox

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    let controller = Unmanaged<SwitcherController>.fromOpaque(refcon!).takeUnretainedValue()
    return controller.handle(type, event)
}

/// Owns ⌘Tab. Keys arrive on a dedicated thread, so a busy main thread can never delay a switch.
/// Switching state lives on that thread; the panel lives on main.
final class SwitcherController {
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private let panel = SwitcherPanel()
    private var switching = false
    private var windows: [WindowSnapshot] = []
    private var selection = 0
    /// With the Settings option on, the panel waits this long before it appears. 71% of ⌘Tab presses (546
    /// measured) are quick taps to the previous window, released within 100 ms; showing the panel for those
    /// only makes it flash. Off by default: the wait itself annoyed its one user.
    static let showDelay: TimeInterval = 0.12
    static let hideOnQuickTapKey = "hideOnQuickTap"
    /// Counts ⌘Tab presses, so a delayed show left over from an earlier press does nothing.
    private var press = 0
    private var panelShown = false

    init() {
        panel.onClick = { [weak self] index in self?.onKeyboardThread { $0.commit(index) } }
    }

    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        var installed = false
        let thread = Thread { [self] in
            let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: CGEventMask(mask), callback: tapCallback,
                                    userInfo: Unmanaged.passUnretained(self).toOpaque())
            guard let tap else {
                ready.signal()
                return
            }
            runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            installed = true
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "flick.keyboard"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        if installed { log.info("Event tap installed") } else { log.error("Couldn't create the event tap. Is Accessibility granted?") }
        return installed
    }

    private func onKeyboardThread(_ work: @escaping (SwitcherController) -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { work(self) }
        CFRunLoopWakeUp(runLoop)
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let command = event.flags.contains(.maskCommand)
        let shift = event.flags.contains(.maskShift)

        if type == .flagsChanged {
            if switching && !command { commit(selection) }
            if !switching && command && (key == kVK_Command || key == kVK_RightCommand) { SecureInput.logIfBlocking() }
            return Unmanaged.passUnretained(event)
        }

        if !switching {
            guard type == .keyDown, key == kVK_Tab, command, !Rules.frontAppKeepsCommandTab() else {
                return Unmanaged.passUnretained(event)
            }
            begin(backward: shift)
            return nil
        }

        // While switching, every key is ours so nothing leaks into the front app.
        if type == .keyDown {
            switch key {
            case kVK_Tab: move(shift ? -1 : 1)
            case kVK_DownArrow, kVK_RightArrow: move(1)
            case kVK_UpArrow, kVK_LeftArrow: move(-1)
            case kVK_Escape: end()
            case kVK_Return, kVK_ANSI_KeypadEnter: commit(selection)
            case kVK_ANSI_W: closeSelected()
            case kVK_ANSI_Q: quitSelected()
            default: break
            }
        }
        return nil
    }

    private func begin(backward: Bool) {
        let started = mach_absolute_time()
        windows = WindowTracker.shared.snapshot()
        log.notice("window list \(msSince(started), format: .fixed(precision: 1), privacy: .public) ms, \(self.windows.count, privacy: .public) windows")
        guard !windows.isEmpty else { return }
        switching = true
        // The first row is usually the window you're on, so start one below it.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let start = windows.first?.pid == frontPID ? 1 : 0
        selection = backward ? windows.count - 1 : min(start, windows.count - 1)
        guard UserDefaults.standard.bool(forKey: Self.hideOnQuickTapKey) else { return showPanel() }
        press += 1
        let press = press
        // Timed off the main thread, so a busy main thread can't make the panel late.
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + Self.showDelay) { [weak self] in
            self?.onKeyboardThread { $0.showPanelIfPending(press) }
        }
    }

    private func showPanelIfPending(_ press: Int) {
        guard switching, !panelShown, press == self.press else { return }
        showPanel()
    }

    /// Shows the panel now, or redraws it with the current rows and selection.
    private func showPanel() {
        panelShown = true
        let windows = windows, selection = selection
        DispatchQueue.main.async { self.panel.show(windows, selection: selection) }
    }

    private func move(_ step: Int) {
        guard !windows.isEmpty else { return }
        selection = ((selection + step) % windows.count + windows.count) % windows.count
        // Navigating means you want to see the list, so a pending panel shows right away.
        guard panelShown else { return showPanel() }
        let selection = selection
        DispatchQueue.main.async { self.panel.select(selection) }
    }

    private func commit(_ index: Int) {
        guard switching else { return }
        let chosen = windows.indices.contains(index) ? windows[index] : nil
        end()
        if let chosen { Actions.focus(chosen) }
    }

    private func closeSelected() {
        guard windows.indices.contains(selection), !windows[selection].isWindowless else { return }
        let wid = windows[selection].wid
        Actions.close(windows[selection])
        dropRows { $0.wid == wid }
    }

    private func quitSelected() {
        guard windows.indices.contains(selection) else { return }
        let pid = windows[selection].pid
        Actions.quit(windows[selection])
        dropRows { $0.pid == pid }
    }

    private func dropRows(where predicate: (WindowSnapshot) -> Bool) {
        windows.removeAll(where: predicate)
        if windows.isEmpty { return end() }
        selection = min(selection, windows.count - 1)
        showPanel()
    }

    private func end() {
        switching = false
        windows = []
        guard panelShown else { return }
        panelShown = false
        DispatchQueue.main.async { self.panel.orderOut(nil) }
    }
}
