import Cocoa

/// Things the Switcher does to a window.
enum Actions {
    /// Accessibility calls block until the target app answers, so they never run on the keyboard thread.
    private static let queue = DispatchQueue(label: "fabaka.actions", qos: .userInteractive)

    /// Runs on the keyboard thread. The WindowServer calls come first and don't wait on the target app;
    /// only the raise inside the app's own window stack does, and that runs after, off this thread.
    static func focus(_ window: WindowSnapshot) {
        if window.isWindowless { return reopen(window.app) }
        let started = mach_absolute_time()
        WindowTracker.shared.promote(window.wid)
        if window.isMinimized || window.app.isHidden {
            // These need the app to cooperate before the window can come forward.
            queue.async {
                if window.app.isHidden { window.app.unhide() }
                if window.isMinimized {
                    AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
                bringForward(window)
                AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            }
            return
        }
        bringForward(window)
        log.notice("focus \(window.appName, privacy: .public): window server \(msSince(started), format: .fixed(precision: 1), privacy: .public) ms")
        Diagnostics.timeUntilFront(window, since: started)
        queue.async {
            let raise = mach_absolute_time()
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            log.notice("focus \(window.appName, privacy: .public): app raise \(msSince(raise), format: .fixed(precision: 1), privacy: .public) ms")
        }
    }

    private static func bringForward(_ window: WindowSnapshot) {
        var psn = ProcessSerialNumber()
        let t0 = mach_absolute_time()
        getProcessForPID(window.pid, &psn)
        let t1 = mach_absolute_time()
        _SLPSSetFrontProcessWithOptions(&psn, window.wid, kUserGeneratedFront)
        let t2 = mach_absolute_time()
        makeKeyWindow(&psn, window.wid)
        log.notice("focus split: psn \(Diagnostics.ms(t0, t1), format: .fixed(precision: 1), privacy: .public) ms, front \(Diagnostics.ms(t1, t2), format: .fixed(precision: 1), privacy: .public) ms, key \(msSince(t2), format: .fixed(precision: 1), privacy: .public) ms")
    }

    /// What a Dock click does: activates the app and asks it to reopen, so most apps open a new window.
    private static func reopen(_ app: NSRunningApplication) {
        DispatchQueue.main.async {
            if app.isHidden { app.unhide() }
            guard let url = app.bundleURL else { app.activate(); return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error { log.error("reopen \(app.localizedName ?? "", privacy: .public): \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    static func close(_ window: WindowSnapshot) {
        guard !window.isWindowless else { return }
        queue.async {
            guard let button = window.element.element(kAXCloseButtonAttribute) else { return }
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    static func quit(_ window: WindowSnapshot) {
        window.app.terminate()
    }
}
