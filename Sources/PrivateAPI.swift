import Cocoa

// Private calls, the same ones AltTab and yabai use. See docs/adr/0002-private-window-server-calls.md.

/// Window ID behind an Accessibility element.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Builds an Accessibility element from a raw token. This is the only way to reach windows on other Spaces.
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

/// Brings a process and one of its windows to the front, switching Space if needed.
@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo") @discardableResult
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

/// Public but hidden from Swift because it's deprecated. There is no replacement that returns a PSN.
@_silgen_name("GetProcessForPID") @discardableResult
func getProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

let kUserGeneratedFront: UInt32 = 0x200

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

/// Spaces a window belongs to, filtered by a mask. Closing a window with `orderOut:` keeps its Space.
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ wids: CFArray) -> Unmanaged<CFArray>?

/// Mask for Spaces currently shown on any display (includes-current | includes-user).
let kCGSSpaceVisible: Int32 = 5

/// Makes `wid` its app's key window with a synthetic mouse-down aimed far outside the window, so nothing
/// inside it gets clicked. Byte layout copied from AltTab's `makeKeyWindow` (SkyLight.framework.swift).
func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
    var wid = wid
    var point = CGPoint(x: 300_000, y: 300_000)
    var bytes = [UInt8](repeating: 0, count: 0x100)
    bytes[0x04] = 0xf8
    bytes[0x3a] = 0x10
    memcpy(&bytes[0x3c], &wid, MemoryLayout<CGWindowID>.size)
    memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)
    bytes[0x08] = 0x01 // left mouse down
    SLPSPostEventRecordTo(&psn, &bytes)
}

extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func bool(_ attribute: String) -> Bool? { value(attribute) as? Bool }

    func element(_ attribute: String) -> AXUIElement? {
        guard let v = value(attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    func elements(_ attribute: String) -> [AXUIElement] { (value(attribute) as? [AXUIElement]) ?? [] }

    var windowID: CGWindowID? {
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(self, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    var pid: pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(self, &pid) == .success else { return nil }
        return pid
    }

    /// Finds window elements of `pid` that `kAXWindows` hides (other Spaces) by walking element IDs within a
    /// time budget. Ported from AltTab's `bruteForceElements`.
    static func windowsByBruteForce(pid: pid_t, wids: Set<CGWindowID>, budget: TimeInterval = 0.25) -> [AXUIElement] {
        var remaining = wids
        var found: [AXUIElement] = []
        guard !remaining.isEmpty, let token = CFDataCreateMutable(nil, 20) else { return found }
        CFDataSetLength(token, 20)
        guard let bytes = CFDataGetMutableBytePtr(token) else { return found }
        memset(bytes, 0, 20)
        var pidField = pid
        memcpy(bytes, &pidField, 4)
        var magic = Int32(0x636f636f) // "coco"
        memcpy(bytes + 8, &magic, 4)
        let deadline = Date().addingTimeInterval(budget)
        var id: UInt64 = 0
        while !remaining.isEmpty, Date() < deadline {
            var idField = id
            memcpy(bytes + 12, &idField, 8)
            id += 1
            guard let element = _AXUIElementCreateWithRemoteToken(token)?.takeRetainedValue(),
                  let wid = element.windowID, remaining.contains(wid),
                  element.string(kAXRoleAttribute) == kAXWindowRole else { continue }
            found.append(element)
            remaining.remove(wid)
        }
        return found
    }
}

/// Milliseconds since a `mach_absolute_time` reading. Used for latency logs.
func msSince(_ start: UInt64) -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return Double(mach_absolute_time() - start) * Double(info.numer) / Double(info.denom) / 1_000_000
}
