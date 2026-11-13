import Cocoa

extension Notification.Name {
    static let residentsChanged = Notification.Name("FlickResidentsChanged")
}

/// Resident apps: they are meant to run all the time, so the Switcher never offers them as windowless apps
/// to quit. Their windows are listed as usual. The list lives in UserDefaults; the Settings window edits it.
final class Residents {
    static let shared = Residents()

    private static let key = "residentBundleIDs"
    /// Finder relaunches itself; Tailscale keeps the VPN up from the menu bar; Ghostty serves its quick
    /// terminal from a global hotkey. Tailscale ships as two bundles: standalone and App Store.
    private static let defaultIDs = ["com.apple.finder", "io.tailscale.ipn.macsys", "io.tailscale.ipn.macos", "com.mitchellh.ghostty"]

    private let lock = NSLock()
    private var ids: [String]

    private init() {
        UserDefaults.standard.register(defaults: [Self.key: Self.defaultIDs])
        ids = UserDefaults.standard.stringArray(forKey: Self.key) ?? Self.defaultIDs
    }

    /// In the order they were added. Any thread.
    var bundleIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return ids
    }

    /// Any thread.
    func contains(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return bundleIDs.contains(id)
    }

    func add(_ id: String) {
        update { if !$0.contains(id) { $0.append(id) } }
    }

    func remove(_ id: String) {
        update { $0.removeAll { $0 == id } }
    }

    private func update(_ change: (inout [String]) -> Void) {
        lock.lock()
        let before = ids
        change(&ids)
        let after = ids
        lock.unlock()
        guard after != before else { return }
        UserDefaults.standard.set(after, forKey: Self.key)
        DispatchQueue.main.async { NotificationCenter.default.post(name: .residentsChanged, object: nil) }
    }
}
