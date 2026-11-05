import Cocoa
import Carbon.HIToolbox

/// How long ⌘ must stay held before the Switcher appears. Same as AltTab's default.
private let showDelay: TimeInterval = 0.1

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    let controller = Unmanaged<SwitcherController>.fromOpaque(refcon!).takeUnretainedValue()
    return controller.handle(type, event)
}

/// Owns ⌘Tab: reads keys from an event tap and drives the Switcher.
final class SwitcherController {
    private var tap: CFMachPort?
    private let panel = SwitcherPanel()
    private var switching = false
    private var windows: [TrackedWindow] = []
    private var selection = 0
    private var showTimer: Timer?

    init() {
        panel.onClick = { [weak self] index in self?.commit(index) }
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log.error("Couldn't create the event tap. Is Accessibility granted?")
            return false
        }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log.info("Event tap installed")
        return true
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
        windows = WindowTracker.shared.orderedWindows()
        guard !windows.isEmpty else { return }
        switching = true
        // The first row is usually the window you're on, so start one below it.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let start = windows.first?.pid == frontPID ? 1 : 0
        selection = backward ? windows.count - 1 : min(start, windows.count - 1)
        showTimer = Timer.scheduledTimer(withTimeInterval: showDelay, repeats: false) { [weak self] _ in
            guard let self, self.switching else { return }
            self.panel.show(self.windows, selection: self.selection)
        }
    }

    private func move(_ step: Int) {
        guard !windows.isEmpty else { return }
        selection = ((selection + step) % windows.count + windows.count) % windows.count
        panel.select(selection)
    }

    private func commit(_ index: Int) {
        guard switching else { return }
        let chosen = windows.indices.contains(index) ? windows[index] : nil
        end()
        if let chosen { Actions.focus(chosen) }
    }

    private func closeSelected() {
        guard windows.indices.contains(selection) else { return }
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

    private func dropRows(where predicate: (TrackedWindow) -> Bool) {
        windows.removeAll(where: predicate)
        if windows.isEmpty { return end() }
        selection = min(selection, windows.count - 1)
        if panel.isVisible { panel.show(windows, selection: selection) }
    }

    private func end() {
        switching = false
        showTimer?.invalidate()
        showTimer = nil
        panel.orderOut(nil)
        windows = []
    }
}
