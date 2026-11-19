import Foundation
import AppKit
import IOKit.ps
import Combine

// MARK: - Battery Protection & Sleep Guard Manager (AlDente Pro Replacement)

/// Trình quản trị Khóa Sạc Pin 80% & Chế độ Bảo vệ Khi Ngủ (Sleep Guard).
///
/// Hoạt động thuần Event-Driven qua IOKit RunLoop Callback:
/// - Khi không có thay đổi về pin, tiến trình hoàn toàn ngủ nhàn rỗi (0.00% CPU).
/// - Khóa sạc 80% Native (không cần root trên macOS 15+ Sequoia).
/// - Sleep Guard giám sát quá trình gập nắp máy, tự động ngắt Bluetooth chống thức ngầm trong balo.
@MainActor
public final class BatteryProtectionManager: ObservableObject {
    public static let shared = BatteryProtectionManager()

    // MARK: - State Properties (Published)

    @Published public var isProtectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isProtectionEnabled, forKey: "cfinder_battery_protection_enabled")
            evaluateProtection()
        }
    }

    @Published public var chargeLimit: Int {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: "cfinder_battery_charge_limit")
            evaluateProtection()
        }
    }

    @Published public private(set) var currentLevel: Int = 100
    @Published public private(set) var isPluggedIn: Bool = false
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var isBypassActive: Bool = false

    @Published public private(set) var batteryHealthPercent: Int = 100
    @Published public private(set) var cycleCount: Int = 0
    @Published public private(set) var batteryTemperature: Double = 0.0

    // MARK: - Sleep Guard State

    @Published public var isSleepGuardEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSleepGuardEnabled, forKey: "cfinder_sleep_guard_enabled")
        }
    }

    @Published public var sleepGuardTurnOffBluetooth: Bool {
        didSet {
            UserDefaults.standard.set(sleepGuardTurnOffBluetooth, forKey: "cfinder_sleep_guard_bluetooth")
        }
    }

    @Published public private(set) var lastSleepReport: String = ""

    // MARK: - Internal Variables

    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var sleepDate: Date?
    private var sleepBatteryLevel: Int = 0
    private var wasBluetoothTurnedOffBySleepGuard: Bool = false

    // MARK: - Init & Lifecycle

    private init() {
        // Mặc định bật bảo vệ sạc 80%
        if UserDefaults.standard.object(forKey: "cfinder_battery_protection_enabled") == nil {
            self.isProtectionEnabled = true
        } else {
            self.isProtectionEnabled = UserDefaults.standard.bool(forKey: "cfinder_battery_protection_enabled")
        }

        let savedLimit = UserDefaults.standard.integer(forKey: "cfinder_battery_charge_limit")
        self.chargeLimit = savedLimit >= 80 ? savedLimit : 80

        // Mặc định bật Sleep Guard
        if UserDefaults.standard.object(forKey: "cfinder_sleep_guard_enabled") == nil {
            self.isSleepGuardEnabled = true
        } else {
            self.isSleepGuardEnabled = UserDefaults.standard.bool(forKey: "cfinder_sleep_guard_enabled")
        }

        if UserDefaults.standard.object(forKey: "cfinder_sleep_guard_bluetooth") == nil {
            self.sleepGuardTurnOffBluetooth = true
        } else {
            self.sleepGuardTurnOffBluetooth = UserDefaults.standard.bool(forKey: "cfinder_sleep_guard_bluetooth")
        }

        setupPowerSourceNotifications()
        setupSleepObservers()
        refreshBatteryMetrics()
        evaluateProtection()
    }

    deinit {
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Event-Driven Power Source Notifications (0% CPU)

    private func setupPowerSourceNotifications() {
        let callback: IOPowerSourceCallbackType = { _ in
            Task { @MainActor in
                let manager = BatteryProtectionManager.shared
                manager.refreshBatteryMetrics()
                manager.evaluateProtection()
            }
        }

        if let source = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            self.powerSourceRunLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    // MARK: - Sleep Guard Lifecycle

    private func setupSleepObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleWillSleep() {
        guard isSleepGuardEnabled else { return }

        sleepDate = Date()
        sleepBatteryLevel = currentLevel

        // Đảm bảo mức giới hạn sạc được giữ vững trước khi máy đi vào giấc ngủ
        if isProtectionEnabled && NativePowerUIClient.shared.isSupported {
            _ = NativePowerUIClient.shared.setLimit(chargeLimit)
        }

        // Tự động tắt Bluetooth nếu được bật để tránh chuột/bàn phím Bluetooth đánh thức máy trong balo
        if sleepGuardTurnOffBluetooth && BluetoothManager.shared.isAvailable && BluetoothManager.shared.isPowerOn {
            wasBluetoothTurnedOffBySleepGuard = true
            BluetoothManager.shared.isPowerOn = false
        }
    }

    @objc private func handleDidWake() {
        guard isSleepGuardEnabled else { return }

        // Khôi phục Bluetooth nếu trước đó được tắt bởi Sleep Guard
        if wasBluetoothTurnedOffBySleepGuard && BluetoothManager.shared.isAvailable {
            BluetoothManager.shared.isPowerOn = true
            wasBluetoothTurnedOffBySleepGuard = false
        }

        // Tính toán thời gian ngủ và mức tiêu hao năng lượng
        if let start = sleepDate {
            let elapsed = Date().timeIntervalSince(start)
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60

            refreshBatteryMetrics()
            let drain = max(0, sleepBatteryLevel - currentLevel)

            let timeStr = hours > 0 ? "\(hours) giờ \(minutes) phút" : "\(minutes) phút"
            if drain > 0 {
                self.lastSleepReport = "Đã ngủ \(timeStr). Tiêu hao: \(drain)% pin."
            } else {
                self.lastSleepReport = "Đã ngủ \(timeStr). Tiêu hao: 0% pin."
            }
            sleepDate = nil
        }

        evaluateProtection()
    }

    // MARK: - Battery Metrics Reading

    public func refreshBatteryMetrics() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            if let cur = desc[kIOPSCurrentCapacityKey] as? Int {
                self.currentLevel = cur
            }

            if let psState = desc[kIOPSPowerSourceStateKey] as? String {
                self.isPluggedIn = (psState == kIOPSACPowerValue)
            }

            if let charging = desc[kIOPSIsChargingKey] as? Bool {
                self.isCharging = charging
            }

            if let maxCap = desc[kIOPSMaxCapacityKey] as? Int,
               let designCap = desc[kIOPSDesignCapacityKey] as? Int, designCap > 0 {
                self.batteryHealthPercent = min(100, max(0, Int(Double(maxCap) / Double(designCap) * 100.0)))
            }

            if let cycles = desc["Cycle Count"] as? Int {
                self.cycleCount = cycles
            }

            // Kiểm tra trạng thái Bypass trực tiếp từ SMC (chạy nguồn trực tiếp từ sạc)
            let smcBypassed = AppleSMCClient.shared.isHardwareBypassed()
            let nativeLimitActive = NativePowerUIClient.shared.isSupported && NativePowerUIClient.shared.isCurrentlyEnabled()
            self.isBypassActive = (smcBypassed || (nativeLimitActive && isPluggedIn && currentLevel >= chargeLimit))

            // Đọc nhiệt độ pin
            if let temp = AppleSMCClient.shared.readBatteryTemperature() {
                self.batteryTemperature = temp
            }
            break
        }
    }

    // MARK: - Protection Evaluation

    public func evaluateProtection() {
        guard isPluggedIn else {
            self.isBypassActive = false
            return
        }

        if isProtectionEnabled {
            // macOS 15+ Native PowerUI (0 Root, 0 Sudo)
            if NativePowerUIClient.shared.isSupported && chargeLimit >= 80 {
                if !NativePowerUIClient.shared.isCurrentlyEnabled() || NativePowerUIClient.shared.currentLimit() != chargeLimit {
                    _ = NativePowerUIClient.shared.setLimit(chargeLimit)
                }
            }
            if currentLevel >= chargeLimit {
                self.isBypassActive = true
            }
        } else {
            // Mở khóa toàn phần 100%
            if NativePowerUIClient.shared.isSupported && NativePowerUIClient.shared.isCurrentlyEnabled() {
                _ = NativePowerUIClient.shared.disable()
            }
            self.isBypassActive = false
        }
    }

    /// Chuyển đổi nhanh bật/tắt chế độ Khóa sạc 80%
    public func toggleProtection() {
        isProtectionEnabled.toggle()
    }
}
