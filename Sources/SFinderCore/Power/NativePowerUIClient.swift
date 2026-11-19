import Foundation
import AppKit

// MARK: - Native Apple Silicon PowerUI Client (macOS 15+ Sequoia & Modern Firmware)

/// Điều khiển giới hạn sạc pin tối đa (MCL - Maximum Charge Limit) gốc của Apple.
///
/// Hoạt động 100% trong User space thông qua Private Framework `PowerUI.framework`.
/// Không yêu cầu quyền root, không cần sudo, không can thiệp thô bạo vào SMC phần cứng.
@MainActor
public final class NativePowerUIClient: Sendable {
    public static let shared = NativePowerUIClient()

    private var clientInstance: AnyObject?
    public private(set) var isSupported: Bool = false

    private init() {
        guard let bundle = Bundle(path: "/System/Library/PrivateFrameworks/PowerUI.framework"), bundle.load() else {
            return
        }
        guard let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else {
            return
        }
        let selInit = NSSelectorFromString("initWithClientName:")
        guard cls.instancesRespond(to: selInit) else { return }

        let selAlloc = NSSelectorFromString("alloc")
        guard cls.responds(to: selAlloc) else { return }
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> AnyObject
        let allocFn = unsafeBitCast(cls.method(for: selAlloc), to: AllocFn.self)
        let uninit = allocFn(cls, selAlloc)

        typealias InitFn = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
        let initFn = unsafeBitCast(cls.instanceMethod(for: selInit), to: InitFn.self)
        let client = initFn(uninit, selInit, "CFinder" as NSString)
        self.clientInstance = client

        let selSupported = NSSelectorFromString("isMCLSupported")
        if let client = client as? NSObject, client.responds(to: selSupported) {
            typealias BoolFn = @convention(c) (AnyObject, Selector) -> Bool
            let fn = unsafeBitCast(client.method(for: selSupported), to: BoolFn.self)
            self.isSupported = fn(client, selSupported)
        }
    }

    /// Đặt giới hạn sạc tối đa (chỉ hỗ trợ 80, 85, 90, 95, 100 trên firmware Apple Silicon).
    @discardableResult
    public func setLimit(_ limit: Int) -> Bool {
        guard isSupported, let client = clientInstance as? NSObject else { return false }
        guard limit >= 80 else { return false }

        let selSet = NSSelectorFromString("setMCLLimit:error:")
        guard client.responds(to: selSet) else { return false }
        typealias SetFn = @convention(c) (AnyObject, Selector, UInt8, UnsafeMutableRawPointer?) -> Bool
        let targetLimit = UInt8(min(max(limit, 80), 100))
        return unsafeBitCast(client.method(for: selSet), to: SetFn.self)(client, selSet, targetLimit, nil)
    }

    /// Hủy bỏ giới hạn sạc (cho phép sạc đầy 100%).
    @discardableResult
    public func disable() -> Bool {
        guard isSupported, let client = clientInstance as? NSObject else { return false }

        let selDisable = NSSelectorFromString("disableMCL:error:")
        guard client.responds(to: selDisable) else { return false }
        typealias DisableFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Bool
        return unsafeBitCast(client.method(for: selDisable), to: DisableFn.self)(client, selDisable, nil)
    }

    /// Kiểm tra tính năng giới hạn sạc MCL hiện có đang bật hay không.
    public func isCurrentlyEnabled() -> Bool {
        guard isSupported, let client = clientInstance as? NSObject else { return false }

        let selEnabled = NSSelectorFromString("isMCLCurrentlyEnabled:")
        guard client.responds(to: selEnabled) else { return false }
        typealias EnabledFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Bool
        return unsafeBitCast(client.method(for: selEnabled), to: EnabledFn.self)(client, selEnabled, nil)
    }

    /// Đọc mức giới hạn hiện tại đang được áp dụng.
    public func currentLimit() -> Int {
        guard isSupported, let client = clientInstance as? NSObject else { return 100 }

        let selGet = NSSelectorFromString("getMCLLimit:error:")
        guard client.responds(to: selGet) else { return 100 }
        typealias GetFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> UInt8
        let val = unsafeBitCast(client.method(for: selGet), to: GetFn.self)(client, selGet, nil)
        return Int(val)
    }
}
