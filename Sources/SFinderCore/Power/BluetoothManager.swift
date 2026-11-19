import Foundation
import AppKit

// MARK: - Bluetooth Manager (Native IOBluetooth Dynamic Bridge)

/// Quản lý bật/tắt Bluetooth thông qua `IOBluetooth.framework` nạp động.
///
/// Phục vụ cho tính năng Sleep Guard: tự động ngắt kết nối Bluetooth khi gập máy
/// để tránh chuột/bàn phím/tai nghe Bluetooth vô tình đánh thức máy trong balo.
public final class BluetoothManager: @unchecked Sendable {
    public static let shared = BluetoothManager()

    private typealias GetPowerStateFunc = @convention(c) () -> Int32
    private typealias SetPowerStateFunc = @convention(c) (Int32) -> Int32

    private var getPowerState: GetPowerStateFunc?
    private var setPowerState: SetPowerStateFunc?
    private var isLoaded: Bool = false

    private init() {
        loadFramework()
    }

    private func loadFramework() {
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY) else {
            return
        }
        if let symGet = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") {
            getPowerState = unsafeBitCast(symGet, to: GetPowerStateFunc.self)
        }
        if let symSet = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") {
            setPowerState = unsafeBitCast(symSet, to: SetPowerStateFunc.self)
        }
        isLoaded = (getPowerState != nil && setPowerState != nil)
    }

    /// Kiểm tra quyền và khả năng sử dụng API Bluetooth.
    /// Không bao giờ gọi API nếu bundle thiếu key `NSBluetoothAlwaysUsageDescription` để tránh crash TCC.
    public var isAvailable: Bool {
        guard isLoaded else { return false }
        guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil else {
            return false
        }
        return true
    }

    public var isPowerOn: Bool {
        get {
            guard isAvailable, let getPower = getPowerState else { return true }
            return getPower() != 0
        }
        set {
            guard isAvailable, let setPower = setPowerState else { return }
            _ = setPower(newValue ? 1 : 0)
        }
    }
}
