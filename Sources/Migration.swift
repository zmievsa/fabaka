import Foundation

/// Fabaka was called Flick, with bundle ID com.zmievsa.flick. On first launch it copies Flick's settings
/// over, so renaming the app keeps your Resident apps and quick-tap wait. Uninstalling Flick with Homebrew
/// (without --zap) leaves those settings on disk.
enum FabakaMigration {
    private static let oldDomain = "com.zmievsa.flick"
    private static let doneKey = "migratedFromFlick"
    private static let keys = ["residentBundleIDs", "quickTapDelayMs"]

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey), let old = UserDefaults(suiteName: oldDomain) else { return }
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) {
                defaults.set(value, forKey: key)
                log.notice("Carried \(key, privacy: .public) over from Flick")
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
