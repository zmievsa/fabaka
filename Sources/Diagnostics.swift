import Cocoa

/// Temporary latency probes. Remove once switching speed is settled.
enum Diagnostics {
    private static let queue = DispatchQueue(label: "fabaka.diagnostics", qos: .utility)

    static func ms(_ a: UInt64, _ b: UInt64) -> Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(b - a) * Double(info.numer) / Double(info.denom) / 1_000_000
    }

    /// Polls the on-screen window order until `window` is the top normal window, then logs how long that took.
    static func timeUntilFront(_ window: WindowSnapshot, since start: UInt64) {
        queue.async {
            for _ in 0..<200 {
                if WindowTracker.cgWindows(onScreenOnly: true).first?.wid == window.wid {
                    log.notice("focus \(window.appName, privacy: .public): on top after \(msSince(start), format: .fixed(precision: 1), privacy: .public) ms")
                    return
                }
                usleep(5_000)
            }
            log.notice("focus \(window.appName, privacy: .public): not on top after 1 s")
        }
    }
}
