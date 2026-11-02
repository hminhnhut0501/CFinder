import SwiftUI
import AppKit
import SFinderCore

/// Minimal Control Center for macOS Menu Bar
/// Focused strictly on quick toggles (Bật/Tắt) and essential one-click utilities
public struct MenuBarControlCenterView: View {
    @ObservedObject private var power = PowerManager.shared
    @ObservedObject private var net = NetworkSpeedMonitor.shared
    @ObservedObject private var snap = WindowSnapManager.shared
    @ObservedObject private var menuBarIcons = MenuBarIconManager.shared
    @ObservedObject private var monitor = SystemMonitorEngine.shared
    @ObservedObject private var netEngine = NetworkMonitorEngine.shared
    @ObservedObject private var recorder = ScreenRecorderEngine.shared
    
    public let onDismissMenu: () -> Void
    
    @State private var isStudioHovered: Bool = false
    @State private var isSettingsHovered: Bool = false
    @State private var isQuitHovered: Bool = false
    
    private var isNetworkActive: Bool {
        if case .networkIdle = power.currentSession {
            return true
        }
        return false
    }
    
    public init(onDismissMenu: @escaping () -> Void = {}) {
        self.onDismissMenu = onDismissMenu
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            // MARK: - Header
            headerBar
            
            // MARK: - Master Toggle 1: Chống ngủ Mac (Keep-Awake)
            masterWakeToggleTile
            
            // MARK: - Master Toggle 2: Tự ngủ khi tải xong
            smartDownloadToggleTile
            
            // MARK: - 2-Column Toggles: Snap Areas & Ẩn Menu Bar
            HStack(spacing: 8) {
                quickToggleTile(
                    title: "Snap Areas",
                    subtitle: snap.isSnapEnabled ? "Đang bật" : "Đã tắt",
                    icon: "rectangle.split.2x2",
                    isActive: snap.isSnapEnabled
                ) {
                    snap.isSnapEnabled.toggle()
                }
                
                quickToggleTile(
                    title: "Ẩn Menu Bar",
                    subtitle: menuBarIcons.isCollapsed ? "Đang ẩn" : "Hiện tất cả",
                    icon: "menubar.rectangle",
                    isActive: menuBarIcons.isCollapsed
                ) {
                    menuBarIcons.toggle()
                }
            }
            
            // MARK: - 3 Quick Utility Buttons (OCR, Record, Scroll)
            quickActionsBar
            
            // MARK: - Minimal Hardware & Network Glance
            systemGlanceBar
            
            // MARK: - Open Studio Primary Button
            openStudioButton
        }
        .padding(12)
        .frame(width: 320)
        .background(
            ZStack {
                Color(red: 0.11, green: 0.11, blue: 0.13)
                
                if power.isActive {
                    RadialGradient(
                        colors: [Color(hex: "F59E0B").opacity(0.10), Color.clear],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 200
                    )
                }
            }
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
    
    // MARK: - 1. Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(nsImage: BrandAssets.appIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .cornerRadius(5)
            
            Text("CFinder")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            // Settings Button
            Button(action: {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    HostActionCoordinator.shared.presentDashboard(tab: .general)
                }
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(isSettingsHovered ? .white : .white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(isSettingsHovered ? 0.08 : 0.03)))
            }
            .buttonStyle(.plain)
            .onHover { isSettingsHovered = $0 }
            
            // Quit Button
            Button(action: {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApplication.shared.terminate(nil)
                }
            }) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isQuitHovered ? .red : .white.opacity(0.45))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(isQuitHovered ? 0.1 : 0.03)))
            }
            .buttonStyle(.plain)
            .onHover { isQuitHovered = $0 }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
    
    // MARK: - 2. Master Wake Toggle Tile
    
    // MARK: - 2. Master Wake Toggle Tile (Chống ngủ Mac với các tuỳ chọn thiết thực)
    
    private var masterWakeToggleTile: some View {
        VStack(spacing: 8) {
            // Main Control Row
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    power.toggleQuickSession()
                }
            }) {
                HStack(spacing: 11) {
                    ZStack {
                        Circle()
                            .fill(power.isActive ? Color(hex: "F59E0B").opacity(0.18) : Color.white.opacity(0.06))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: power.isActive ? "bolt.fill" : "moon.zzz.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(power.isActive ? Color(hex: "F59E0B") : .white.opacity(0.6))
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Chống ngủ Mac")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(power.isActive ? "\(power.formattedRemainingTime) còn lại" : "Chế độ ngủ tự nhiên")
                            .font(.system(size: 10.5))
                            .foregroundColor(power.isActive ? Color(hex: "F59E0B") : .white.opacity(0.45))
                    }
                    
                    Spacer()
                    
                    // Minimal Status Capsule Pill
                    Text(power.isActive ? "BẬT" : "TẮT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(power.isActive ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(power.isActive ? Color(hex: "F59E0B").opacity(0.85) : Color.white.opacity(0.06))
                        )
                }
            }
            .buttonStyle(.plain)
            
            // Quick Duration Presets & Display Sleep Toggle
            HStack(spacing: 4) {
                wakePresetPill(title: "∞ Vô hạn", minutes: 0)
                wakePresetPill(title: "15m", minutes: 15)
                wakePresetPill(title: "30m", minutes: 30)
                wakePresetPill(title: "1h", minutes: 60)
                wakePresetPill(title: "2h", minutes: 120)
                
                Spacer(minLength: 1)
                
                // Display Sleep Toggle
                Button(action: {
                    power.allowDisplaySleep.toggle()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: power.allowDisplaySleep ? "display.slash" : "display")
                            .font(.system(size: 9))
                        Text(power.allowDisplaySleep ? "Màn ngủ" : "Màn sáng")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(power.allowDisplaySleep ? Color(hex: "38BDF8") : .white.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(power.allowDisplaySleep ? Color(hex: "38BDF8").opacity(0.12) : Color.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(power.allowDisplaySleep ? Color(hex: "38BDF8").opacity(0.3) : Color.white.opacity(0.06), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Cho phép màn hình tắt để tiết kiệm pin nhưng CPU vẫn tiếp tục chạy")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(power.isActive ? 0.06 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(power.isActive ? Color(hex: "F59E0B").opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private func wakePresetPill(title: String, minutes: Int) -> some View {
        let isSelected = power.isActive && (
            (minutes == 0 && power.currentSession == .indefinite) ||
            (minutes > 0 && power.currentWakePresetMinutes == minutes)
        )
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
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
                .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 5.5)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color(hex: "F59E0B").opacity(0.85) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 3. Smart Auto-Sleep & Sleep Timer Tile (Tự ngủ thông minh)
    
    private var smartDownloadToggleTile: some View {
        VStack(spacing: 8) {
            // Row 1: Tự ngủ khi tải xong (Network Idle Sleep)
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(isNetworkActive ? Color(hex: "38BDF8").opacity(0.18) : Color.white.opacity(0.06))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isNetworkActive ? Color(hex: "38BDF8") : .white.opacity(0.6))
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tự ngủ khi tải xong")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(isNetworkActive ? "Đang giám sát • \(net.formattedDownloadSpeed)" : "Ngủ máy khi mạng rỗi")
                        .font(.system(size: 10.5))
                        .foregroundColor(isNetworkActive ? Color(hex: "38BDF8") : .white.opacity(0.45))
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        if isNetworkActive {
                            power.endSession(reason: "Người dùng tắt giám sát tải")
                        } else {
                            power.startNetworkIdleSession()
                        }
                    }
                }) {
                    Text(isNetworkActive ? "BẬT" : "TẮT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(isNetworkActive ? .white : .white.opacity(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isNetworkActive ? Color(hex: "0284C7").opacity(0.85) : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            
            // Row 2: Hẹn giờ tự ngủ (Sleep Timer - ban đêm)
            HStack(spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: power.isSleepTimerActive ? "moon.stars.fill" : "moon.stars")
                        .font(.system(size: 9.5))
                        .foregroundColor(power.isSleepTimerActive ? Color(hex: "C084FC") : .white.opacity(0.5))
                    Text(power.isSleepTimerActive ? "Hẹn ngủ: \(power.formattedSleepTimerRemaining)" : "Hẹn giờ ngủ:")
                        .font(.system(size: 9.5, weight: power.isSleepTimerActive ? .bold : .medium))
                        .foregroundColor(power.isSleepTimerActive ? Color(hex: "C084FC") : .white.opacity(0.55))
                }
                
                Spacer(minLength: 2)
                
                if power.isSleepTimerActive {
                    Button(action: {
                        withAnimation {
                            power.cancelSleepTimer()
                        }
                    }) {
                        Text("Huỷ")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color(hex: "EF4444"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color(hex: "EF4444").opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    sleepTimerPresetPill(title: "15m", minutes: 15)
                    sleepTimerPresetPill(title: "30m", minutes: 30)
                    sleepTimerPresetPill(title: "1h", minutes: 60)
                    sleepTimerPresetPill(title: "2h", minutes: 120)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity((isNetworkActive || power.isSleepTimerActive) ? 0.06 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isNetworkActive ? Color(hex: "38BDF8").opacity(0.3) :
                            power.isSleepTimerActive ? Color(hex: "C084FC").opacity(0.3) :
                            Color.white.opacity(0.05),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func sleepTimerPresetPill(title: String, minutes: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                power.startSleepTimer(minutes: minutes, action: .sleepNow)
            }
        }) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 5.5)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 4. Compact 2-Column Toggle Tile
    
    private func quickToggleTile(title: String, subtitle: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? CFinderTheme.primaryLight : .white.opacity(0.5))
                    .frame(width: 18)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(isActive ? CFinderTheme.primaryLight : .white.opacity(0.4))
                }
                
                Spacer(minLength: 0)
                
                Circle()
                    .fill(isActive ? CFinderTheme.primary : Color.white.opacity(0.12))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(isActive ? 0.06 : 0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isActive ? CFinderTheme.primaryLight.opacity(0.25) : Color.white.opacity(0.04), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 5. Quick Actions Bar (OCR, Record, Scroll)
    
    private var quickActionsBar: some View {
        HStack(spacing: 6) {
            // OCR
            actionButton(title: "Quét chữ", icon: "text.viewfinder", badge: "⌥C") {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task {
                        _ = try? await ScreenOCREngine.shared.captureScreenInteractively()
                    }
                }
            }
            
            // Record
            let isRec = recorder.isRecording
            actionButton(
                title: isRec ? "Dừng ghi" : "Ghi hình",
                icon: isRec ? "stop.circle.fill" : "record.circle.fill",
                badge: isRec ? recorder.formattedDuration : "⌥R",
                tint: isRec ? Color(hex: "EF4444") : nil
            ) {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ScreenRecorderEngine.shared.toggleRecording()
                }
            }
            
            // Scroll Capture
            actionButton(title: "Chụp cuộn", icon: "arrow.down.doc.fill", badge: "⌥S") {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    HostActionCoordinator.shared.presentScrollingCapture()
                }
            }
            
            // Edge Quick Notes
            actionButton(title: "Ghi chú", icon: "note.text", badge: "⌥N") {
                onDismissMenu()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    EdgeNotesWindowController.shared.toggleDrawer()
                }
            }
        }
    }
    
    private func actionButton(title: String, icon: String, badge: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(tint ?? .white.opacity(0.85))
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(tint ?? .white.opacity(0.75))
                    .lineLimit(1)
                
                Text(badge)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(tint?.opacity(0.8) ?? .white.opacity(0.35))
            }
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint != nil ? tint!.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(tint != nil ? tint!.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 6. Minimal System Glance
    
    private var systemGlanceBar: some View {
        Button(action: {
            onDismissMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                HostActionCoordinator.shared.presentDashboard(tab: .monitor)
            }
        }) {
            let snap = monitor.snapshot
            let tp = netEngine.throughput
            
            HStack(spacing: 8) {
                Image(systemName: "gauge.medium")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                
                Text("CPU \(Int(snap.cpu.totalUsage))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.2))
                
                Text("RAM \(Int(snap.ram.usagePercentage))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.2))
                
                Text("↓ \(tp.formattedDownloadSpeed)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "38BDF8").opacity(0.9))
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 7. Open Studio Button
    
    private var openStudioButton: some View {
        Button(action: {
            onDismissMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                HostActionCoordinator.shared.presentDashboard(tab: .overview)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 10))
                Text("Mở CFinder Studio")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isStudioHovered ? 0.10 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(isStudioHovered ? 0.15 : 0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isStudioHovered = $0 }
    }
}
