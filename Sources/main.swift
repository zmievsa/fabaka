import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        FabakaMigration.run() // before anything reads settings
        // A frozen app must not stall Fabaka for the default 6 seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        startAtLogin()
        addMainMenu()
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
        if !switcher.start() { log.error("Fabaka is running but ⌘Tab isn't hooked") }
    }

    /// Opening Fabaka.app again while it runs shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return false
    }

    /// Fabaka has no menu bar of its own (it's an accessory app), but a main menu still gives the Settings
    /// window ⌘W and ⌘Q.
    private func addMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Fabaka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let main = NSMenu()
        for menu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

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
