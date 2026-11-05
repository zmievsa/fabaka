import Cocoa

/// Things the Switcher does to a window. Accessibility calls block on the target app, so they run off main.
enum Actions {
    private static let queue = DispatchQueue(label: "flick.actions", qos: .userInteractive)

    static func focus(_ window: TrackedWindow) {
        WindowTracker.shared.promote(window.wid)
        let app = NSRunningApplication(processIdentifier: window.pid)
        if app?.isHidden == true { app?.unhide() }
        queue.async {
            if window.element.bool(kAXMinimizedAttribute) == true {
                AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            var psn = ProcessSerialNumber()
            getProcessForPID(window.pid, &psn)
            _SLPSSetFrontProcessWithOptions(&psn, window.wid, kUserGeneratedFront)
            makeKeyWindow(&psn, window.wid)
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
    }

    static func close(_ window: TrackedWindow) {
        queue.async {
            guard let button = window.element.element(kAXCloseButtonAttribute) else { return }
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    static func quit(_ window: TrackedWindow) {
        NSRunningApplication(processIdentifier: window.pid)?.terminate()
    }
}
