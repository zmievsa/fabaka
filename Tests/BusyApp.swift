import Cocoa

// A stand-in for an app that is still starting up at login: it shows one titled window, but while the
// file named by FLICK_TEST_UNREADY exists it answers Accessibility without exposing that window. Its
// window list comes back empty and the window doesn't call itself a window, the way an app looks while
// it is still restoring its windows. Removing the file makes it an ordinary app, with no new window
// appearing and no notification sent.

private let unreadyFlag = ProcessInfo.processInfo.environment["FLICK_TEST_UNREADY"]
private var unready: Bool { unreadyFlag.map { FileManager.default.fileExists(atPath: $0) } ?? false }

final class BusyApplication: NSApplication {
    override func accessibilityWindows() -> [Any]? { unready ? [] : super.accessibilityWindows() }
}

final class BusyWindow: NSWindow {
    override func accessibilityRole() -> NSAccessibility.Role? { unready ? .unknown : super.accessibilityRole() }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = BusyWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
                                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = ProcessInfo.processInfo.environment["FLICK_TEST_TITLE"] ?? "Busy window"
        window.orderFront(nil)
        self.window = window
    }
}

let app = BusyApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
