import SwiftUI
import AppKit
import SFinderCore

/// Helper tính toán dung lượng ổ đĩa gốc macOS
enum DiskSpaceHelper {
    static var info: (freeText: String, usagePercent: Double) {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let freeSize = attrs[.systemFreeSize] as? Int64,
           let totalSize = attrs[.systemSize] as? Int64,
           totalSize > 0 {
            let used = totalSize - freeSize
            let percent = Double(used) / Double(totalSize) * 100.0
            let freeGB = Double(freeSize) / 1_073_741_824.0
            let freeText = freeGB >= 1000 ? String(format: "%.1f TB trống", freeGB / 1024.0) : String(format: "%.0f GB trống", freeGB)
            return (freeText, percent)
        }
        return ("--", 0.0)
    }
}

/// Chuẩn thiết kế Apple Control Center 3.0 Pro (macOS Liquid Glass Popover)
public struct MenuBarControlCenterView: View {
    @ObservedObject private var power = PowerManager.shared
    @ObservedObject private var net = NetworkSpeedMonitor.shared
    @ObservedObject private var snap = WindowSnapManager.shared
    @ObservedObject private var menuBarIcons = MenuBarIconManager.shared
    @ObservedObject private var monitor = SystemMonitorEngine.shared
    @ObservedObject private var netEngine = NetworkMonitorEngine.shared
    @ObservedObject private var recorder = ScreenRecorderEngine.shared
    @ObservedObject private var battery = BatteryProtectionManager.shared
    
    public let onDismissMenu: () -> Void
    
    @State private var isStudioHovered: Bool = false
    @State private var isSettingsHovered: Bool = false
    @State private var isQuitHovered: Bool = false
    @State private var isNetworkCardHovered: Bool = false
    @State private var isMonitorCardHovered: Bool = false
    @State private var isSleepTimerPickerExpanded: Bool = false
    
    public init(onDismissMenu: @escaping () -> Void = {}) {
        self.onDismissMenu = onDismissMenu
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            keepAwakeHeroCard
            batteryProtectionCard
            coreModulesGrid
            workspaceTogglesGrid
            quickActionsAndStudioRow
            footerRow
        }
        .padding(10)
        .frame(width: 366)
        .background(popoverBackground)
        .focusable(false)
        .focusEffectDisabled()
    }
    
    private var popoverBackground: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
            Color.black.opacity(0.12)
            if power.isActive {
                RadialGradient(
                    colors: [Color(hex: "F59E0B").opacity(0.14), Color.clear],
                    center: .topLeading,
                    startRadius: 5,
                    endRadius: 260
                )
            }
        }
    }
    
    // MARK: - 1. Chống ngủ Mac (Full-Width Card)
    
    private var keepAwakeHeroCard: some View {
        VStack(spacing: 8) {
            keepAwakeHeaderRow
            Divider().background(Color.white.opacity(0.06))
            keepAwakePresetsRow
            Divider().background(Color.white.opacity(0.06))
            keepAwakeOptionsRow
            if isSleepTimerPickerExpanded && !power.isSleepTimerActive {
                keepAwakeTimerPickerRow
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(0.11), lineWidth: 0.8))
    }
    
    private var keepAwakeHeaderRow: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                power.toggleQuickSession()
            }
        }) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(power.isActive ? Color(hex: "F59E0B") : Color.white.opacity(0.08))
                        .frame(width: 30, height: 30)
                        .shadow(color: power.isActive ? Color(hex: "F59E0B").opacity(0.45) : .clear, radius: 5)
                    
                    Image(systemName: power.isActive ? "bolt.fill" : "moon.zzz.fill")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(power.isActive ? .black : .white.opacity(0.65))
                }
                
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("Chống ngủ Mac")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(power.isActive ? "\(power.formattedRemainingTime) còn lại" : "Chế độ ngủ tự nhiên")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(power.isActive ? Color(hex: "F59E0B") : .white.opacity(0.5))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 8)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(power.isActive ? Color.black : Color.white.opacity(0.25))
                        .frame(width: 5, height: 5)
                    Text(power.isActive ? "ĐANG BẬT" : "ĐÃ TẮT")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(power.isActive ? .black : .white.opacity(0.6))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule().fill(power.isActive ? Color(hex: "F59E0B") : Color.white.opacity(0.07))
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help("Bấm để Bật/Tắt giữ máy thức nhanh")
    }
    
    private var keepAwakePresetsRow: some View {
        HStack(spacing: 5) {
            presetPillButton(title: "Vô hạn", minutes: 0, tooltip: "Giữ thức không giới hạn")
            presetPillButton(title: "15 phút", minutes: 15, tooltip: "Giữ thức 15 phút")
            presetPillButton(title: "30 phút", minutes: 30, tooltip: "Giữ thức 30 phút")
            presetPillButton(title: "1 giờ", minutes: 60, tooltip: "Giữ thức 1 giờ")
            presetPillButton(title: "2 giờ", minutes: 120, tooltip: "Giữ thức 2 giờ")
        }
    }
    
    private var keepAwakeOptionsRow: some View {
        HStack(spacing: 6) {
            displaySleepButton
            Spacer(minLength: 4)
            sleepTimerButton
        }
    }
    
    private var displaySleepButton: some View {
        Button(action: { power.allowDisplaySleep.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: power.allowDisplaySleep ? "display.slash" : "display")
                    .font(.system(size: 9.5))
                Text(power.allowDisplaySleep ? "Màn hình tắt khi ngủ" : "Giữ màn hình sáng")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundColor(power.allowDisplaySleep ? Color(hex: "38BDF8") : .white.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                Capsule()
                    .fill(power.allowDisplaySleep ? Color(hex: "0EA5E9").opacity(0.18) : Color.white.opacity(0.04))
                    .overlay(Capsule().stroke(power.allowDisplaySleep ? Color(hex: "0EA5E9").opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help("Cho phép màn hình tắt tiết kiệm pin nhưng CPU và mạng vẫn giữ thức")
    }
    
    @ViewBuilder
    private var sleepTimerButton: some View {
        if power.isSleepTimerActive {
            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "C084FC"))
                Text("Ngủ sau: \(power.formattedSleepTimerRemaining)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "C084FC"))
                Button("Huỷ") {
                    withAnimation { power.cancelSleepTimer() }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(hex: "EF4444"))
                .padding(.horizontal, 4.5)
                .padding(.vertical, 2)
                .background(Color(hex: "EF4444").opacity(0.16))
                .cornerRadius(4)
            }
        } else {
            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isSleepTimerPickerExpanded.toggle()
                }
            }) {
                HStack(spacing: 3.5) {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 9.5))
                    Text("Hẹn giờ tắt máy")
                        .font(.system(size: 9.5, weight: .medium))
                    Image(systemName: isSleepTimerPickerExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundColor(isSleepTimerPickerExpanded ? Color(hex: "C084FC") : .white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(
                    Capsule()
                        .fill(isSleepTimerPickerExpanded ? Color(hex: "C084FC").opacity(0.18) : Color.white.opacity(0.04))
                        .overlay(Capsule().stroke(isSleepTimerPickerExpanded ? Color(hex: "C084FC").opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help("Bấm để chọn thời gian hẹn giờ đưa máy vào giấc ngủ")
        }
    }
    
    private var keepAwakeTimerPickerRow: some View {
        HStack(spacing: 4) {
            sleepOptionPill("15 phút", 15)
            sleepOptionPill("30 phút", 30)
            sleepOptionPill("1 giờ", 60)
            sleepOptionPill("2 giờ", 120)
        }
        .padding(.top, 2)
    }
    
    private func presetPillButton(title: String, minutes: Int, tooltip: String) -> some View {
        let isSelected: Bool
        if !power.isActive {
            isSelected = false
        } else if minutes == 0 {
            isSelected = (power.currentSession == .indefinite)
        } else if case .timed(let duration, _) = power.currentSession {
            isSelected = abs(duration - Double(minutes * 60)) < 60
        } else {
            isSelected = false
        }
        
        return Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                if isSelected {
                    power.endSession()
                } else if minutes == 0 {
                    power.startIndefiniteSession()
                } else {
                    power.startTimedSession(minutes: minutes)
                }
            }
        }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .black : .white.opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(hex: "F59E0B") : Color.white.opacity(0.05))
                        .shadow(color: isSelected ? Color(hex: "F59E0B").opacity(0.35) : .clear, radius: 3)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help(tooltip)
    }
    
    private func sleepOptionPill(_ title: String, _ minutes: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                power.startSleepTimer(minutes: minutes, action: .sleepNow)
                isSleepTimerPickerExpanded = false
            }
        }) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "C084FC"))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: "C084FC").opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(hex: "C084FC").opacity(0.3), lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
    }
    
    // MARK: - Battery Protection & Sleep Guard (AlDente Pro Replacement)

    private var batteryProtectionCard: some View {
        VStack(spacing: 7) {
            batteryProtectionHeaderRow
            Divider().background(Color.white.opacity(0.06))
            batteryProtectionPresetsRow
            if !battery.lastSleepReport.isEmpty {
                batterySleepReportRow
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(0.11), lineWidth: 0.8))
    }

    private var batteryProtectionHeaderRow: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                battery.toggleProtection()
            }
        }) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(battery.isProtectionEnabled ? Color(hex: "10B981") : Color.white.opacity(0.08))
                        .frame(width: 28, height: 28)
                        .shadow(color: battery.isProtectionEnabled ? Color(hex: "10B981").opacity(0.4) : .clear, radius: 4)

                    Image(systemName: battery.isBypassActive ? "bolt.shield.fill" : (battery.isCharging ? "bolt.batteryblock.fill" : "battery.75percent"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(battery.isProtectionEnabled ? .black : .white.opacity(0.65))
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("Khóa sạc Pin")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("\(battery.currentLevel)%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(battery.isBypassActive ? Color(hex: "34D399") : .white.opacity(0.85))

                        if battery.isBypassActive {
                            Text("Bypass AC")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Color(hex: "10B981"))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(hex: "10B981").opacity(0.18))
                                .cornerRadius(3)
                        }
                    }

                    Text(batterySubtitleText)
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                Text(battery.isProtectionEnabled ? "\(battery.chargeLimit)%" : "TẮT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(battery.isProtectionEnabled ? Color(hex: "10B981") : .white.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(battery.isProtectionEnabled ? Color(hex: "10B981").opacity(0.18) : Color.white.opacity(0.05))
                    )
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help("Bấm để Bật/Tắt khóa sạc pin (bảo vệ tuổi thọ cell pin)")
    }

    private var batterySubtitleText: String {
        if battery.isBypassActive {
            return "Chạy nguồn điện lưới trực tiếp (ngắt sạc)"
        } else if battery.isCharging {
            return "Đang sạc lên ngưỡng \(battery.chargeLimit)%"
        } else if battery.isPluggedIn {
            return "Đã cắm sạc • Pin \(battery.currentLevel)%"
        } else {
            return "Đang dùng pin • Sức khỏe \(battery.batteryHealthPercent)%"
        }
    }

    private var batteryProtectionPresetsRow: some View {
        HStack(spacing: 4) {
            batteryLimitPill(80)
            batteryLimitPill(85)
            batteryLimitPill(90)
            batteryLimitPill(100)

            Spacer(minLength: 2)

            Button(action: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    battery.isSleepGuardEnabled.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: battery.isSleepGuardEnabled ? "shield.lefthalf.filled" : "shield.slash")
                        .font(.system(size: 9))
                    Text("Sleep Guard")
                        .font(.system(size: 9.5, weight: .medium))
                }
                .foregroundColor(battery.isSleepGuardEnabled ? Color(hex: "C084FC") : .white.opacity(0.55))
                .padding(.horizontal, 6.5)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(battery.isSleepGuardEnabled ? Color(hex: "C084FC").opacity(0.18) : Color.white.opacity(0.04))
                        .overlay(Capsule().stroke(battery.isSleepGuardEnabled ? Color(hex: "C084FC").opacity(0.35) : Color.white.opacity(0.06), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .help("Tự động ngắt sạc và Bluetooth khi gập máy, chống nóng máy và hao pin trong balo")
        }
    }

    private func batteryLimitPill(_ limit: Int) -> some View {
        let isSelected = battery.isProtectionEnabled && (battery.chargeLimit == limit)
        let label = limit == 100 ? "100%" : "\(limit)%"

        return Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                if !battery.isProtectionEnabled {
                    battery.isProtectionEnabled = true
                }
                battery.chargeLimit = limit
            }
        }) {
            Text(label)
                .font(.system(size: 9.5, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .black : .white.opacity(0.75))
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(hex: "10B981") : Color.white.opacity(0.05))
                        .shadow(color: isSelected ? Color(hex: "10B981").opacity(0.35) : .clear, radius: 2)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
    }

    private var batterySleepReportRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: 8.5))
                .foregroundColor(Color(hex: "C084FC"))
            Text(battery.lastSleepReport)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
    }
    
    // MARK: - 2. Core Modules: Mạng & Ổ đĩa SSD (Side-by-side)
    
    private var coreModulesGrid: some View {
        HStack(spacing: 8) {
            networkCard
            storageAndSystemCard
        }
        .frame(height: 114)
    }
    
    private var networkCard: some View {
        Button(action: {
            onDismissMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                HostActionCoordinator.shared.presentDashboard(tab: .network)
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                networkHeaderRow
                networkDownloadRow
                networkUploadRow
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(isNetworkCardHovered ? 0.10 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(isNetworkCardHovered ? 0.18 : 0.11), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { isNetworkCardHovered = $0 }
        .help("Bấm để xem chi tiết Lưu lượng & Tốc độ Mạng")
    }
    
    private var networkHeaderRow: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(Color(hex: "0EA5E9").opacity(0.18)).frame(width: 22, height: 22)
                Image(systemName: "network").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "38BDF8"))
            }
            Text("Tốc độ mạng")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Circle().fill(Color(hex: "10B981")).frame(width: 5, height: 5).shadow(color: Color(hex: "10B981").opacity(0.8), radius: 2)
        }
    }
    
    private var networkDownloadRow: some View {
        let tp = netEngine.throughput
        return HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "38BDF8"))
            
            VStack(alignment: .leading, spacing: 0) {
                Text(tp.formattedDownloadSpeed)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Tải xuống")
                    .font(.system(size: 8.5))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
    
    private var networkUploadRow: some View {
        let tp = netEngine.throughput
        return HStack(spacing: 6) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "F472B6"))
            
            VStack(alignment: .leading, spacing: 0) {
                Text(tp.formattedUploadSpeed)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Tải lên")
                    .font(.system(size: 8.5))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
    
    private var storageAndSystemCard: some View {
        Button(action: {
            onDismissMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                HostActionCoordinator.shared.presentDashboard(tab: .cleaner)
            }
        }) {
            VStack(alignment: .leading, spacing: 5.5) {
                storageHeaderRow
                storageGaugeSection
                hardwareGaugesRow
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(isMonitorCardHovered ? 0.10 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(isMonitorCardHovered ? 0.18 : 0.11), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { isMonitorCardHovered = $0 }
        .help("Bấm để mở Dọn dẹp rác hệ thống & Gỡ ứng dụng tận gốc")
    }
    
    private var storageHeaderRow: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(Color(hex: "10B981").opacity(0.18)).frame(width: 22, height: 22)
                Image(systemName: "internaldrive.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "34D399"))
            }
            Text("Ổ đĩa SSD")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 6.5, weight: .bold)).foregroundColor(.white.opacity(0.3))
        }
    }
    
    private var storageGaugeSection: some View {
        let disk = DiskSpaceHelper.info
        return statGaugeRow(
            label: "Dung lượng trống",
            value: disk.freeText,
            ratio: min(1.0, max(0.04, disk.usagePercent / 100.0)),
            gradient: [Color(hex: "059669"), Color(hex: "34D399")]
        )
    }
    
    private var hardwareGaugesRow: some View {
        let snapData = monitor.snapshot
        return HStack(spacing: 8) {
            miniStatGauge(
                label: "CPU",
                value: "\(Int(snapData.cpu.totalUsage))%",
                ratio: min(1.0, max(0.04, snapData.cpu.totalUsage / 100.0)),
                gradient: [Color(hex: "0EA5E9"), Color(hex: "38BDF8")]
            )
            
            miniStatGauge(
                label: "RAM",
                value: "\(Int(snapData.ram.usagePercentage))%",
                ratio: min(1.0, max(0.04, snapData.ram.usagePercentage / 100.0)),
                gradient: [Color(hex: "8B5CF6"), Color(hex: "C084FC")]
            )
        }
    }
    
    private func statGaugeRow(label: String, value: String, ratio: Double, gradient: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 8.5, weight: .medium)).foregroundColor(.white.opacity(0.55))
                Spacer()
                Text(value).font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "34D399"))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(height: 3)
                    Capsule().fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, proxy.size.width * CGFloat(ratio)), height: 3)
                }
            }
            .frame(height: 3)
        }
    }
    
    private func miniStatGauge(label: String, value: String, ratio: Double, gradient: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 8.5, weight: .medium)).foregroundColor(.white.opacity(0.55))
                Spacer()
                Text(value).font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.9))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(height: 2.5)
                    Capsule().fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(2.5, proxy.size.width * CGFloat(ratio)), height: 2.5)
                }
            }
            .frame(height: 2.5)
        }
    }
    
    // MARK: - 3. Workspace Toggles (Snap Areas + Ẩn Menu Bar)
    
    private var workspaceTogglesGrid: some View {
        HStack(spacing: 8) {
            // Snap Areas
            workspaceCapsuleButton(
                title: "Snap Areas",
                subtitle: snap.isSnapEnabled ? "Đang bật" : "Đã tắt",
                icon: "rectangle.split.2x2",
                isActive: snap.isSnapEnabled,
                activeColor: Color(hex: "007AFF")
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    snap.isSnapEnabled.toggle()
                }
            }
            
            // Ẩn Menu Bar
            workspaceCapsuleButton(
                title: "Ẩn Menu Bar",
                subtitle: menuBarIcons.isCollapsed ? "Đang ẩn bớt" : "Hiện tất cả",
                icon: "menubar.rectangle",
                isActive: menuBarIcons.isCollapsed,
                activeColor: Color(hex: "6366F1")
            ) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    menuBarIcons.toggle()
                }
            }
        }
    }
    
    private func workspaceCapsuleButton(
        title: String,
        subtitle: String,
        icon: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(isActive ? activeColor : Color.white.opacity(0.08))
                        .frame(width: 26, height: 26)
                        .shadow(color: isActive ? activeColor.opacity(0.4) : .clear, radius: 4)
                    
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(isActive ? .white : .white.opacity(0.65))
                }
                
                VStack(alignment: .leading, spacing: 0.5) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(isActive ? activeColor.opacity(0.9) : .white.opacity(0.42))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                Circle()
                    .fill(isActive ? activeColor : Color.white.opacity(0.12))
                    .frame(width: 5, height: 5)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(isActive ? activeColor.opacity(0.3) : Color.white.opacity(0.10), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
    }
    
    // MARK: - 4. Quick Utilities Strip & Studio
    
    private var utilityButtonsStrip: some View {
        HStack(spacing: 8) {
            // 1. Quét chữ OCR
            circularIconButton(icon: "text.viewfinder", tint: Color(hex: "38BDF8"), tooltip: "Quét chữ OCR (⌥C)") {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task { _ = try? await ScreenOCREngine.shared.captureScreenInteractively() }
                }
            }
            
            // 2. Ghi hình
            let isRec = recorder.isRecording
            circularIconButton(icon: isRec ? "stop.circle.fill" : "record.circle.fill", tint: isRec ? Color(hex: "EF4444") : Color(hex: "F43F5E"), tooltip: isRec ? "Dừng ghi hình" : "Ghi hình (⌥R)") {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ScreenRecorderEngine.shared.toggleRecording()
                }
            }
            
            // 3. Chụp cuộn
            circularIconButton(icon: "arrow.down.doc.fill", tint: Color(hex: "C084FC"), tooltip: "Chụp cuộn trang dài (⌥S)") {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    HostActionCoordinator.shared.presentScrollingCapture()
                }
            }
            
            // 4. Ghi chú mép
            circularIconButton(icon: "note.text", tint: Color(hex: "FBBF24"), tooltip: "Ghi chú mép màn hình (⌥N)") {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    EdgeNotesWindowController.shared.toggleDrawer()
                }
            }
        }
    }
    
    private var studioLaunchButton: some View {
        Button(action: {
            onDismissMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                HostActionCoordinator.shared.presentDashboard(tab: .overview)
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CFinderTheme.primaryLight)
                
                Text("Studio")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                
                Text("⌘O")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white.opacity(0.12)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(isStudioHovered ? 0.14 : 0.08))
                    .overlay(Capsule().stroke(Color.white.opacity(isStudioHovered ? 0.25 : 0.12), lineWidth: 0.8))
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { isStudioHovered = $0 }
        .help("Mở bảng điều khiển trung tâm CFinder Studio (⌘O)")
    }
    
    private var quickActionsAndStudioRow: some View {
        HStack(spacing: 8) {
            utilityButtonsStrip
            
            Spacer(minLength: 4)
            
            studioLaunchButton
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.white.opacity(0.11), lineWidth: 0.8))
    }
    
    private func circularIconButton(icon: String, tint: Color, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7))
                
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(tint)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help(tooltip)
    }
    
    // MARK: - 5. Minimal Footer (Settings & Quit)
    
    private var footerRow: some View {
        HStack {
            HStack(spacing: 4.5) {
                Circle().fill(Color(hex: "10B981")).frame(width: 5, height: 5)
                Text("CFinder sẵn sàng").font(.system(size: 9.5, weight: .medium)).foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Button(action: {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    HostActionCoordinator.shared.presentDashboard(tab: .general)
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10.5))
                    .foregroundColor(isSettingsHovered ? .white : .white.opacity(0.55))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(isSettingsHovered ? 0.10 : 0.04)))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .onHover { isSettingsHovered = $0 }
            .help("Cài đặt tổng quan")
            
            Button(action: {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApplication.shared.terminate(nil)
                }
            }) {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isQuitHovered ? Color(hex: "EF4444") : .white.opacity(0.45))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(isQuitHovered ? Color(hex: "EF4444").opacity(0.16) : Color.white.opacity(0.04)))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .onHover { isQuitHovered = $0 }
            .help("Thoát CFinder hoàn toàn")
        }
        .padding(.horizontal, 4)
        .padding(.top, 1)
    }
}
