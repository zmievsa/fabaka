import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private var started = false
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A frozen app must not stall Flick for the default 6 seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        startAtLogin()
        addStatusItem()
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

    /// Opening Flick.app again while it runs shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }

    private func addStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Flick")
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openSettings() { SettingsWindow.shared.show() }

    private func startAtLogin() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"), SMAppService.mainApp.status != .enabled else { return }
        do { try SMAppService.mainApp.register() } catch { log.error("Login item: \(error.localizedDescription)") }
    }
}

signal(SIGUSR1, SIG_IGN) // WindowTracker turns it into a debug dump once it starts.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
