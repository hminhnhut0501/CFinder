import Foundation
import AppKit
import IOKit.pwr_mgt
import IOKit.ps

public enum WakeSessionType: Equatable, Sendable {
    case indefinite
    case timed(duration: TimeInterval, endDate: Date)
    case appRunning(bundleId: String, appName: String)
    case networkIdle(thresholdKB: Double, safetyDuration: Int, action: SystemPowerAction)
}

@MainActor
public final class PowerManager: ObservableObject {
    public static let shared = PowerManager()
    
    // MARK: - State Properties
    
    @Published public private(set) var isActive: Bool = false
    @Published public private(set) var currentSession: WakeSessionType?
    @Published public private(set) var remainingSeconds: TimeInterval = 0
    
    // MARK: - Sleep Timer (Hẹn giờ ngủ máy tự động)
    @Published public private(set) var isSleepTimerActive: Bool = false
    @Published public private(set) var sleepTimerRemainingSeconds: TimeInterval = 0
    @Published public var sleepTimerAction: SystemPowerAction = .sleepNow
    @Published public private(set) var sleepTimerWarningSeconds: Int? = nil
    
    private var sleepTimer: Timer?
    private var sleepTimerTargetDate: Date?
    
    @Published public var allowDisplaySleep: Bool {
        didSet {
            UserDefaults.standard.set(allowDisplaySleep, forKey: "sfinder_wake_allowDisplaySleep")
            if isActive {
                reapplyAssertion()
            }
        }
    }
    
    @Published public var stopOnLowBattery: Bool {
        didSet {
            UserDefaults.standard.set(stopOnLowBattery, forKey: "sfinder_wake_stopOnLowBattery")
        }
    }
    
    // MARK: - Internal IOKit Handle
    
    private var assertionID: IOPMAssertionID = 0
    private var countdownTimer: Timer?
    private var appTerminationObserver: Any?
    private var batteryCheckTimer: Timer?
    
    // MARK: - Init
    
    private init() {
        self.allowDisplaySleep = UserDefaults.standard.bool(forKey: "sfinder_wake_allowDisplaySleep")
        // Default stop on low battery to true if not set
        if UserDefaults.standard.object(forKey: "sfinder_wake_stopOnLowBattery") == nil {
            self.stopOnLowBattery = true
        } else {
            self.stopOnLowBattery = UserDefaults.standard.bool(forKey: "sfinder_wake_stopOnLowBattery")
        }
    }
    
    // MARK: - Public Controls
    
    /// Bắt đầu phiên giữ thức không giới hạn thời gian (Indefinite)
    public func startIndefiniteSession() {
        startSession(type: .indefinite)
    }
    
    /// Bắt đầu phiên giữ thức theo phút
    public func startTimedSession(minutes: Int) {
        let seconds = TimeInterval(minutes * 60)
        let endDate = Date().addingTimeInterval(seconds)
        startSession(type: .timed(duration: seconds, endDate: endDate))
    }
    
    /// Bắt đầu phiên giữ thức theo giờ
    public func startTimedSession(hours: Int) {
        let seconds = TimeInterval(hours * 3600)
        let endDate = Date().addingTimeInterval(seconds)
        startSession(type: .timed(duration: seconds, endDate: endDate))
    }
    
    /// Bắt đầu phiên giữ thức cho đến khi ứng dụng chỉ định tắt
    public func startAppSession(app: NSRunningApplication) {
        let name = app.localizedName ?? "Ứng dụng"
        let bundleId = app.bundleIdentifier ?? UUID().uuidString
        startSession(type: .appRunning(bundleId: bundleId, appName: name))
    }
    
    /// Bắt đầu phiên giữ thức thông minh dựa trên tốc độ mạng (Download / Upload xong tự động ngủ hoặc tắt máy)
    public func startNetworkIdleSession(
        thresholdKB: Double? = nil,
        safetyDuration: Int? = nil,
        action: SystemPowerAction? = nil
    ) {
        let thresh = thresholdKB ?? NetworkSpeedMonitor.shared.thresholdKBps
        let safety = safetyDuration ?? NetworkSpeedMonitor.shared.safetyDurationSeconds
        let act = action ?? NetworkSpeedMonitor.shared.selectedAction
        startSession(type: .networkIdle(thresholdKB: thresh, safetyDuration: safety, action: act))
    }
    
    /// Bật / Tắt nhanh phiên giữ thức (Quick Toggle)
    public func toggleQuickSession() {
        if isActive {
            endSession(reason: "Người dùng tắt thủ công")
        } else {
            startIndefiniteSession()
        }
    }
    
    /// Kết thúc phiên giữ thức hiện tại
    public func endSession(reason: String = "Kết thúc phiên giữ thức") {
        guard isActive else { return }
        
        releaseAssertion()
        stopTimers()
        removeAppObserver()
        NetworkSpeedMonitor.shared.stopMonitoring()
        
        self.isActive = false
        self.currentSession = nil
        self.remainingSeconds = 0
        
        NSLog("[PowerManager] Wake session ended: %@", reason)
        postNotification(title: "CFinder — Đã dừng giữ thức", message: "Mac sẽ chuyển sang chế độ ngủ tự động theo cài đặt hệ thống.")
    }
    
    // MARK: - Sleep Timer Methods (Hẹn giờ tự động ngủ máy)
    
    public var formattedSleepTimerRemaining: String {
        let total = Int(sleepTimerRemainingSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        } else {
            return String(format: "%02dm %02ds", minutes, seconds)
        }
    }
    
    public var currentWakePresetMinutes: Int? {
        guard isActive else { return nil }
        if case .timed(let duration, _) = currentSession {
            return Int(round(duration / 60))
        } else if case .indefinite = currentSession {
            return 0 // 0 = Vô hạn
        }
        return nil
    }
    
    public func startSleepTimer(minutes: Int, action: SystemPowerAction = .sleepNow) {
        cancelSleepTimer()
        self.sleepTimerAction = action
        let seconds = TimeInterval(minutes * 60)
        self.sleepTimerRemainingSeconds = seconds
        self.sleepTimerTargetDate = Date().addingTimeInterval(seconds)
        self.isSleepTimerActive = true
        self.sleepTimerWarningSeconds = nil
        
        postNotification(
            title: "CFinder — Đã hẹn giờ tự ngủ",
            message: "Máy Mac sẽ tự động \(action.title.lowercased()) sau \(minutes) phút."
        )
        
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let target = self.sleepTimerTargetDate else { return }
                let rem = max(0, target.timeIntervalSinceNow)
                self.sleepTimerRemainingSeconds = rem
                
                // Cảnh báo 15 giây trước khi thực thi
                if rem <= 15 && rem > 0 {
                    self.sleepTimerWarningSeconds = Int(ceil(rem))
                    if Int(rem) == 15 {
                        self.postNotification(
                            title: "CFinder — Chuẩn bị ngủ máy",
                            message: "Máy Mac sẽ tự động \(self.sleepTimerAction.title.lowercased()) sau 15 giây."
                        )
                    }
                }
                
                if rem <= 0 {
                    self.cancelSleepTimer()
                    self.endSession(reason: "Hết giờ hẹn ngủ máy")
                    self.sleepTimerAction.execute()
                }
            }
        }
    }
    
    public func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerTargetDate = nil
        isSleepTimerActive = false
        sleepTimerRemainingSeconds = 0
        sleepTimerWarningSeconds = nil
    }
    
    // MARK: - Core Assertion Handling
    
    private func startSession(type: WakeSessionType) {
        // Clear any existing active session cleanly
        if isActive {
            releaseAssertion()
            stopTimers()
            removeAppObserver()
        }
        
        let success = createAssertion()
        guard success else {
            NSLog("[PowerManager] Failed to create IOKit power assertion")
            return
        }
        
        self.isActive = true
        self.currentSession = type
        
        switch type {
        case .indefinite:
            self.remainingSeconds = 0
            postNotification(title: "CFinder — Đang giữ thức (Không giới hạn)", message: "Mac sẽ duy trì hoạt động liên tục cho đến khi bạn dừng.")
            
        case .timed(let duration, let endDate):
            self.remainingSeconds = duration
            startCountdownTimer(endDate: endDate)
            let formatted = formatDuration(duration)
            postNotification(title: "CFinder — Đang giữ thức (\(formatted))", message: "Mac sẽ giữ thức trong \(formatted).")
            
        case .appRunning(let bundleId, let appName):
            self.remainingSeconds = 0
            setupAppObserver(bundleId: bundleId, appName: appName)
            postNotification(title: "CFinder — Giữ thức theo ứng dụng", message: "Duy trì thức khi \(appName) đang mở.")
            
        case .networkIdle(let thresh, let safety, let action):
            self.remainingSeconds = 0
            NetworkSpeedMonitor.shared.startMonitoring(thresholdKB: thresh, safetyDuration: safety, action: action) { [weak self] act in
                Task { @MainActor [weak self] in
                    self?.endSession(reason: "Hoàn tất tải tệp (\(safety)s an toàn)")
                    self?.postNotification(
                        title: "CFinder — Đã xong tải tệp",
                        message: "Kích hoạt hành động: \(act.title)"
                    )
                    act.execute()
                }
            }
            postNotification(
                title: "CFinder — Tự động \(action.title) khi tải xong",
                message: "Giữ thức thông minh khi tốc độ > \(Int(thresh)) KB/s. Sẽ \(action.title) sau \(safety)s an toàn."
            )
        }
        
        startBatteryMonitoring()
    }
    
    private func createAssertion() -> Bool {
        let assertionType = allowDisplaySleep
            ? kIOPMAssertionTypePreventUserIdleSystemSleep
            : kIOPMAssertionTypePreventUserIdleDisplaySleep
        
        let reason = "CFinder: Smart Power & Wake Management Session" as CFString
        let result = IOPMAssertionCreateWithName(
            assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        
        return result == kIOReturnSuccess
    }
    
    private func releaseAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
    
    private func reapplyAssertion() {
        guard isActive else { return }
        releaseAssertion()
        _ = createAssertion()
    }
    
    // MARK: - Timers & Observers
    
    private func startCountdownTimer(endDate: Date) {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let rem = max(0, endDate.timeIntervalSinceNow)
                self.remainingSeconds = rem
                if rem <= 0 {
                    self.endSession(reason: "Hết thời gian giữ thức đã định")
                }
            }
        }
    }
    
    private func setupAppObserver(bundleId: String, appName: String) {
        removeAppObserver()
        appTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier == bundleId {
                Task { @MainActor [weak self] in
                    self?.endSession(reason: "Ứng dụng \(appName) đã đóng")
                }
            }
        }
    }
    
    private func removeAppObserver() {
        if let observer = appTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appTerminationObserver = nil
        }
    }
    
    private func startBatteryMonitoring() {
        batteryCheckTimer?.invalidate()
        guard stopOnLowBattery else { return }
        
        batteryCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isActive, self.stopOnLowBattery else { return }
                if let batteryLevel = self.getCurrentBatteryLevel(), !self.isCharging(), batteryLevel <= 10 {
                    self.endSession(reason: "Pin yếu (\(batteryLevel)%) — Tự động ngắt giữ thức để bảo vệ pin")
                }
            }
        }
    }
    
    private func stopTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        batteryCheckTimer?.invalidate()
        batteryCheckTimer = nil
    }
    
    // MARK: - Battery Helpers
    
    private func getCurrentBatteryLevel() -> Int? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for ps in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
               let cap = desc[kIOPSCurrentCapacityKey as String] as? Int {
                return cap
            }
        }
        return nil
    }
    
    private func isCharging() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return true
        }
        for ps in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any],
               let isCharging = desc[kIOPSIsChargingKey as String] as? Bool {
                return isCharging
            }
        }
        return false
    }
    
    // MARK: - Notifications
    
    private func postNotification(title: String, message: String) {
        let center = NSUserNotificationCenter.default
        let notif = NSUserNotification()
        notif.title = title
        notif.informativeText = message
        notif.soundName = NSUserNotificationDefaultSoundName
        center.deliver(notif)
    }
    
    // MARK: - Formatting Helpers
    
    public var formattedRemainingTime: String {
        guard isActive else { return "Không hoạt động" }
        switch currentSession {
        case .indefinite:
            return "Không giới hạn (Indefinite)"
        case .timed:
            let total = Int(remainingSeconds)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let seconds = total % 60
            if hours > 0 {
                return String(format: "%02d:%02d:%02d còn lại", hours, minutes, seconds)
            } else {
                return String(format: "%02d:%02d còn lại", minutes, seconds)
            }
        case .appRunning(_, let appName):
            return "Khi \(appName) đang chạy"
        case .networkIdle(let thresh, let safety, let action):
            let monitor = NetworkSpeedMonitor.shared
            if let warnSec = monitor.countdownWarningSeconds {
                return "CẢNH BÁO: \(action.title) sau \(warnSec)s!"
            } else if monitor.consecutiveIdleSeconds > 0 {
                return "An toàn: \(monitor.consecutiveIdleSeconds)/\(safety)s (↓\(monitor.formattedDownloadSpeed))"
            } else {
                return "Đang tải: ↓\(monitor.formattedDownloadSpeed) (Ngưỡng: \(Int(thresh))KB/s)"
            }
        case .none:
            return "Không hoạt động"
        }
    }
    
    public var compactBadgeString: String? {
        guard isActive else { return nil }
        switch currentSession {
        case .indefinite:
            return "∞"
        case .timed:
            let total = Int(remainingSeconds)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            if hours > 0 {
                return "\(hours)h\(minutes)m"
            } else if minutes > 0 {
                return "\(minutes)m"
            } else {
                return "\(total)s"
            }
        case .appRunning:
            return "App"
        case .networkIdle:
            return "↓\(NetworkSpeedMonitor.shared.formattedDownloadSpeed)"
        case .none:
            return nil
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m > 0 ? "\(h) giờ \(m) phút" : "\(h) giờ"
        }
        return "\(mins) phút"
    }
}
