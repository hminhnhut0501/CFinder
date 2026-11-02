import Foundation
import Darwin
import Combine

public enum NetworkMonitorDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case downloadOnly = "download_only"
    case both = "both"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .downloadOnly: return "Chỉ giám sát Tải xuống (Download)"
        case .both: return "Cả Tải xuống & Tải lên (Download & Upload)"
        }
    }
}

@MainActor
public final class NetworkSpeedMonitor: ObservableObject {
    public static let shared = NetworkSpeedMonitor()
    
    // MARK: - Published Live States
    
    @Published public private(set) var downloadSpeedBytesPerSec: Double = 0
    @Published public private(set) var uploadSpeedBytesPerSec: Double = 0
    @Published public private(set) var consecutiveIdleSeconds: Int = 0
    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var hasActiveTransferStarted: Bool = false
    @Published public private(set) var countdownWarningSeconds: Int? = nil
    
    // MARK: - User Settings (Persisted in UserDefaults)
    
    @Published public var thresholdKBps: Double {
        didSet { UserDefaults.standard.set(thresholdKBps, forKey: "sfinder_network_threshold_kbps") }
    }
    
    @Published public var safetyDurationSeconds: Int {
        didSet { UserDefaults.standard.set(safetyDurationSeconds, forKey: "sfinder_network_safety_seconds") }
    }
    
    @Published public var monitorDirection: NetworkMonitorDirection {
        didSet { UserDefaults.standard.set(monitorDirection.rawValue, forKey: "sfinder_network_direction") }
    }
    
    @Published public var selectedAction: SystemPowerAction {
        didSet { UserDefaults.standard.set(selectedAction.rawValue, forKey: "sfinder_network_completion_action") }
    }
    
    @Published public var warnBeforeAction: Bool {
        didSet { UserDefaults.standard.set(warnBeforeAction, forKey: "sfinder_network_warn_before_action") }
    }
    
    // MARK: - Internal Engine Mechanics
    
    public var onCompletionTriggered: ((SystemPowerAction) -> Void)?
    
    private var timer: Timer?
    private var warningTimer: Timer?
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private var previousTimestamp: Date = Date()
    private var initialGraceSeconds: Int = 0
    
    private init() {
        let savedThreshold = UserDefaults.standard.double(forKey: "sfinder_network_threshold_kbps")
        self.thresholdKBps = savedThreshold > 0 ? savedThreshold : 100.0
        
        let savedSafety = UserDefaults.standard.integer(forKey: "sfinder_network_safety_seconds")
        self.safetyDurationSeconds = savedSafety > 0 ? savedSafety : 60
        
        if let dirStr = UserDefaults.standard.string(forKey: "sfinder_network_direction"),
           let dir = NetworkMonitorDirection(rawValue: dirStr) {
            self.monitorDirection = dir
        } else {
            self.monitorDirection = .downloadOnly
        }
        
        if let actionStr = UserDefaults.standard.string(forKey: "sfinder_network_completion_action"),
           let act = SystemPowerAction(rawValue: actionStr) {
            self.selectedAction = act
        } else {
            self.selectedAction = .sleepNow
        }
        
        if UserDefaults.standard.object(forKey: "sfinder_network_warn_before_action") == nil {
            self.warnBeforeAction = true
        } else {
            self.warnBeforeAction = UserDefaults.standard.bool(forKey: "sfinder_network_warn_before_action")
        }
    }
    
    // MARK: - Public Controls
    
    public func startMonitoring(
        thresholdKB: Double? = nil,
        safetyDuration: Int? = nil,
        action: SystemPowerAction? = nil,
        onCompletion: ((SystemPowerAction) -> Void)? = nil
    ) {
        if let t = thresholdKB { self.thresholdKBps = t }
        if let s = safetyDuration { self.safetyDurationSeconds = s }
        if let a = action { self.selectedAction = a }
        if let c = onCompletion { self.onCompletionTriggered = c }
        
        stopMonitoring()
        
        let (currentIn, currentOut) = Self.readNetworkBytes64()
        self.previousBytesIn = currentIn
        self.previousBytesOut = currentOut
        self.previousTimestamp = Date()
        self.consecutiveIdleSeconds = 0
        self.hasActiveTransferStarted = false
        self.initialGraceSeconds = 0
        self.countdownWarningSeconds = nil
        self.isMonitoring = true
        
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleNetwork()
            }
        }
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        warningTimer?.invalidate()
        warningTimer = nil
        isMonitoring = false
        consecutiveIdleSeconds = 0
        downloadSpeedBytesPerSec = 0
        uploadSpeedBytesPerSec = 0
        hasActiveTransferStarted = false
        initialGraceSeconds = 0
        countdownWarningSeconds = nil
    }
    
    public func cancelWarning() {
        warningTimer?.invalidate()
        warningTimer = nil
        countdownWarningSeconds = nil
        consecutiveIdleSeconds = 0
    }
    
    // MARK: - Periodic Sampling
    
    private func sampleNetwork() {
        guard isMonitoring else { return }
        
        // If in warning countdown state, let countdown finish or be cancelled
        if countdownWarningSeconds != nil { return }
        
        let now = Date()
        let elapsed = max(0.5, now.timeIntervalSince(previousTimestamp))
        let (currentIn, currentOut) = Self.readNetworkBytes64()
        
        let deltaIn = currentIn >= previousBytesIn ? currentIn - previousBytesIn : 0
        let deltaOut = currentOut >= previousBytesOut ? currentOut - previousBytesOut : 0
        
        self.previousBytesIn = currentIn
        self.previousBytesOut = currentOut
        self.previousTimestamp = now
        
        let inSpeed = Double(deltaIn) / elapsed
        let outSpeed = Double(deltaOut) / elapsed
        
        self.downloadSpeedBytesPerSec = inSpeed
        self.uploadSpeedBytesPerSec = outSpeed
        
        let checkedSpeedKBps: Double
        switch monitorDirection {
        case .downloadOnly:
            checkedSpeedKBps = inSpeed / 1024.0
        case .both:
            checkedSpeedKBps = (inSpeed + outSpeed) / 1024.0
        }
        
        // Threshold comparison
        if checkedSpeedKBps >= thresholdKBps {
            hasActiveTransferStarted = true
            consecutiveIdleSeconds = 0
        } else {
            // Speed is currently below threshold
            if !hasActiveTransferStarted {
                initialGraceSeconds += 1
                // Cho phép 30 giây đầu tiên để người dùng bắt đầu download
                if initialGraceSeconds >= 30 {
                    hasActiveTransferStarted = true
                }
            } else {
                consecutiveIdleSeconds += 1
                if consecutiveIdleSeconds >= safetyDurationSeconds {
                    initiateCompletionFlow()
                }
            }
        }
    }
    
    private func initiateCompletionFlow() {
        let action = self.selectedAction
        
        if warnBeforeAction && (action == .sleepNow || action == .shutDown) {
            startWarningCountdown(action: action)
        } else {
            stopMonitoring()
            onCompletionTriggered?(action)
        }
    }
    
    private func startWarningCountdown(action: SystemPowerAction) {
        countdownWarningSeconds = 10
        warningTimer?.invalidate()
        warningTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let sec = self.countdownWarningSeconds, sec > 1 {
                    self.countdownWarningSeconds = sec - 1
                } else {
                    self.warningTimer?.invalidate()
                    self.warningTimer = nil
                    self.countdownWarningSeconds = nil
                    self.stopMonitoring()
                    self.onCompletionTriggered?(action)
                }
            }
        }
    }
    
    // MARK: - Formatters & UI Helpers
    
    public var formattedDownloadSpeed: String {
        Self.formatSpeed(downloadSpeedBytesPerSec)
    }
    
    public var formattedUploadSpeed: String {
        Self.formatSpeed(uploadSpeedBytesPerSec)
    }
    
    public var safetyProgress: Double {
        guard safetyDurationSeconds > 0 else { return 0 }
        return min(1.0, Double(consecutiveIdleSeconds) / Double(safetyDurationSeconds))
    }
    
    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }
    
    // MARK: - Native Darwin 64-bit Network Packet Counter
    
    public static func readNetworkBytes64() -> (inBytes: UInt64, outBytes: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        if sysctl(&mib, 6, nil, &len, nil, 0) < 0 { return (0, 0) }
        
        var buffer = [UInt8](repeating: 0, count: len)
        if sysctl(&mib, 6, &buffer, &len, nil, 0) < 0 { return (0, 0) }
        
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var offset = 0
        
        while offset < len {
            let msgPtr = buffer.withUnsafeBytes { $0.baseAddress!.advanced(by: offset) }
            let ifm = msgPtr.assumingMemoryBound(to: if_msghdr2.self).pointee
            offset += Int(ifm.ifm_msglen)
            
            if ifm.ifm_type == RTM_IFINFO2 {
                let sdlPtr = msgPtr.advanced(by: MemoryLayout<if_msghdr2>.size).assumingMemoryBound(to: sockaddr_dl.self).pointee
                let n = Int(sdlPtr.sdl_nlen)
                if n > 0 {
                    let namePtr = msgPtr.advanced(by: MemoryLayout<if_msghdr2>.size + MemoryLayout<sockaddr_dl>.size - 12)
                    let nameBytes = [UInt8](UnsafeBufferPointer(start: namePtr.assumingMemoryBound(to: UInt8.self), count: n))
                    let name = String(bytes: nameBytes, encoding: .utf8) ?? ""
                    if !name.hasPrefix("lo") {
                        totalIn += ifm.ifm_data.ifi_ibytes
                        totalOut += ifm.ifm_data.ifi_obytes
                    }
                }
            }
        }
        return (totalIn, totalOut)
    }
}
