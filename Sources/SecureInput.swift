import Cocoa
import Carbon.HIToolbox

/// While any process has Secure Input on, macOS hides key presses from Fabaka, so ⌘Tab falls through to the
/// system switcher. It can get stuck on for the whole session; locking and unlocking the Mac clears that.
enum SecureInput {
    /// Keyboard thread only.
    private static var lastLogged: (pid: pid_t, at: Date)?

    /// Called on the keyboard thread when ⌘ goes down. Logs who blocks ⌘Tab, at most once a minute per holder.
    static func logIfBlocking() {
        guard IsSecureEventInputEnabled() else {
            lastLogged = nil
            return
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let pid = (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value ?? 0
        if let lastLogged, lastLogged.pid == pid, Date().timeIntervalSince(lastLogged.at) < 60 { return }
        lastLogged = (pid, Date())
        // macOS often reports the front app here instead of the real holder, so this is only a hint.
        log.error("⌘Tab is blocked: Secure Input is on, reported holder \(name(of: pid), privacy: .public) (pid \(pid, privacy: .public)). If no password field is open, lock and unlock the Mac.")
    }

    private static func name(of pid: pid_t) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
        var buffer = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : "unknown"
    }
}
