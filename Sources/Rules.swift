import Cocoa

/// Fixed rules, taken from the user's AltTab exceptions. Resident apps are the one list Settings edits.
enum Rules {
    /// Excluded apps: their windows never appear.
    static let excludedBundleIDs: Set<String> = [
        "video.fathom.electron",
        "com.McAfee.McAfeeSafariHost",
    ]

    /// Pass-through apps: they keep ⌘Tab while full screen. Matched by prefix, like AltTab.
    static let passThroughBundlePrefixes = [
        "com.microsoft.rdc.macos",
        "com.teamviewer.TeamViewer",
        "org.virtualbox.app.VirtualBoxVM",
        "com.parallels.",
        "com.citrix.XenAppViewer",
        "com.citrix.receiver.icaviewer.mac",
        "com.nicesoftware.dcvviewer",
        "com.vmware.fusion",
        "com.apple.ScreenSharing",
        "com.utmapp.UTM",
    ]

    static func isExcluded(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return excludedBundleIDs.contains(id)
    }

    /// True when the front app is a pass-through app showing a full-screen window.
    static func frontAppKeepsCommandTab() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              passThroughBundlePrefixes.contains(where: { id.hasPrefix($0) }) else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.05)
        return element.element(kAXFocusedWindowAttribute)?.bool("AXFullScreen") == true
    }
}
