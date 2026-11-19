import Foundation
import IOKit

// MARK: - Direct In-Process AppleSMC Reader (Zero Subprocess, Zero Sudo)

/// Trình đọc trực tiếp phần cứng AppleSMC qua IOKit trong tiến trình.
/// 
/// Đọc các thông số phần cứng như công tắc bypass pin (CHTE, CH0B, bfF0),
/// cảm biến nhiệt độ pin, CPU mà không cần spawn tiến trình con (zero fork/exec),
/// không cần quyền root và an toàn đa luồng.
public final class AppleSMCClient: @unchecked Sendable {
    public static let shared = AppleSMCClient()

    private var conn: io_connect_t = 0
    private let lock = NSLock()

    public init() {
        openIfNeeded()
    }

    deinit {
        lock.lock()
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
        lock.unlock()
    }

    private func openIfNeeded() {
        guard conn == 0 else { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return }
        if IOServiceOpen(svc, mach_task_self_, 0, &conn) != KERN_SUCCESS {
            conn = 0
        }
        IOObjectRelease(svc)
    }

    public static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func call(cmd: UInt8, key: UInt32 = 0, index: UInt32 = 0, size: UInt32 = 0) -> [UInt8]? {
        openIfNeeded()
        guard conn != 0 else { return nil }
        var inp = [UInt8](repeating: 0, count: 80)
        withUnsafeBytes(of: key) { inp.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: size) { inp.replaceSubrange(28..<32, with: $0) }
        inp[42] = cmd
        withUnsafeBytes(of: index) { inp.replaceSubrange(44..<48, with: $0) }
        var out = [UInt8](repeating: 0, count: 80)
        var outSize = 80
        var kr = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
        if kr != KERN_SUCCESS {
            IOServiceClose(conn)
            conn = 0
            openIfNeeded()
            guard conn != 0 else { return nil }
            kr = IOConnectCallStructMethod(conn, 2, inp, 80, &out, &outSize)
            if kr != KERN_SUCCESS { return nil }
        }
        return out
    }

    /// Đọc mảng byte thô từ một SMC Key (ví dụ: "CHTE", "CH0B", "bfF0").
    public func readKeyBytes(_ keyStr: String) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        let k = Self.fourCC(keyStr)
        guard let info = call(cmd: 9, key: k) else { return nil }
        let size = UInt32(info[28])
        guard size > 0, size <= 32 else { return nil }
        guard let out = call(cmd: 5, key: k, size: size) else { return nil }
        return Array(out[0..<Int(size)])
    }

    /// Kiểm tra trạng thái Bypass phần cứng (chạy nguồn trực tiếp từ sạc, không sạc vào pin).
    public func isHardwareBypassed() -> Bool {
        if let chte = readKeyBytes("CHTE"), !chte.isEmpty {
            if chte[0] == 1 { return true }
        }
        if let ch0b = readKeyBytes("CH0B"), !ch0b.isEmpty {
            if ch0b[0] == 2 { return true }
        }
        if let bff0 = readKeyBytes("bfF0"), !bff0.isEmpty {
            if bff0[0] == 1 || bff0[0] == 2 { return true }
        }
        if let bclm = readKeyBytes("BCLM"), !bclm.isEmpty {
            if bclm[0] > 0 && bclm[0] < 100 { return true }
        }
        return false
    }

    /// Đọc nhiệt độ pin từ cảm biến SMC `TB0T` hoặc `TB1T` (°C).
    public func readBatteryTemperature() -> Double? {
        if let bytes = readKeyBytes("TB0T"), bytes.count >= 2 {
            let raw = (Int(bytes[0]) << 6) | (Int(bytes[1]) >> 2)
            return Double(raw) / 4.0
        }
        if let bytes = readKeyBytes("TB1T"), bytes.count >= 2 {
            let raw = (Int(bytes[0]) << 6) | (Int(bytes[1]) >> 2)
            return Double(raw) / 4.0
        }
        return nil
    }
}
