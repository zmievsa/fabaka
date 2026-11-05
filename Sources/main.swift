import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A frozen app must not stall Flick for the default 6 seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        startAtLogin()
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(prompt)
        startWhenTrusted()
    }

    /// Waits for the Accessibility grant, then starts without a relaunch.
    private func startWhenTrusted() {
        guard !started else { return }
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startWhenTrusted() }
            return
        }
        started = true
        WindowTracker.shared.start()
        if !switcher.start() { log.error("Flick is running but ⌘Tab isn't hooked") }
    }

    private func startAtLogin() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"), SMAppService.mainApp.status != .enabled else { return }
        do { try SMAppService.mainApp.register() } catch { log.error("Login item: \(error.localizedDescription)") }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
