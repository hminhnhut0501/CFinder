import SwiftUI
import AppKit
import Carbon
import SFinderCore

public enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "overview"
    case permissions = "permissions"
    case general = "general"
    case ocr = "ocr"
    case recorder = "recorder"
    case wake = "wake"
    case rename = "rename"
    case notes = "notes"
    case snap = "snap"
    case menubar = "menubar"
    case monitor = "monitor"
    case network = "network"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .overview: return "Tổng quan"
        case .permissions: return "Quyền hệ thống"
        case .general: return "Cài đặt chung"
        case .ocr: return "Quét chữ OCR"
        case .recorder: return "Quay màn hình"
        case .wake: return "Chống ngủ Mac"
        case .rename: return "Đổi tên tệp"
        case .notes: return "Ghi chú mép"
        case .snap: return "Snap Areas"
        case .menubar: return "Menu Bar Icons"
        case .monitor: return "Theo dõi hệ thống"
        case .network: return "Mạng & Tốc độ"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .overview: return "Trung tâm điều khiển toàn bộ công cụ và trạng thái vận hành của CFinder"
        case .permissions: return "Kiểm tra và kích hoạt các quyền bảo mật macOS để ứng dụng hoạt động 100%"
        case .general: return "Cấu hình khởi động cùng hệ điều hành, hiển thị Menu Bar và âm thanh thông báo"
        case .ocr: return "Tuỳ biến phím tắt toàn cục, gộp đoạn, xuất bảng tính TSV và mở URL tự động"
        case .recorder: return "Cấu hình quay video 60/120fps Retina, thu âm thanh máy tính, micro và hiệu ứng chuột"
        case .wake: return "Quản lý giữ thức CPU, cho phép tắt màn hình và tự ngắt bảo vệ khi pin yếu"
        case .rename: return "Thiết lập quy tắc đổi tên tệp ưu tiên trên Finder và nhật ký hoàn tác (⌘Z) an toàn"
        case .notes: return "Rê chuột mép phải là mở, gõ tự lưu, đồng bộ Apple Notes  và phím tắt ⌥N"
        case .snap: return "Kéo mép & góc màn hình để chia đôi, chia tư và tuỳ biến từng màn hình"
        case .menubar: return "Giấu bớt biểu tượng thanh menu, tự động ẩn lại sau khi dùng"
        case .monitor: return "Nhiệt độ CPU, GPU; mức dùng CPU, GPU, RAM và áp lực bộ nhớ"
        case .network: return "Tốc độ mạng hiện tại, lưu lượng trực tiếp và đo tốc độ Internet"
        }
    }
    
    public var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .permissions: return "hand.raised.fill"
        case .general: return "gearshape.fill"
        case .ocr: return "text.viewfinder"
        case .recorder: return "record.circle.fill"
        case .wake: return "bolt.fill"
        case .rename: return "pencil.and.list.clipboard"
        case .notes: return "note.text"
        case .snap: return "rectangle.split.2x2"
        case .menubar: return "menubar.rectangle"
        case .monitor: return "gauge.with.dots.needle.bottom.50percent"
        case .network: return "network"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .overview: return CFinderTheme.FeatureColor.overview
        case .permissions: return CFinderTheme.FeatureColor.permissions
        case .general: return CFinderTheme.FeatureColor.general
        case .ocr: return CFinderTheme.FeatureColor.ocr
        case .recorder: return CFinderTheme.FeatureColor.recorder
        case .wake: return CFinderTheme.FeatureColor.wake
        case .rename: return CFinderTheme.FeatureColor.rename
        case .notes: return CFinderTheme.FeatureColor.notes
        case .snap: return CFinderTheme.FeatureColor.snap
        case .menubar: return CFinderTheme.FeatureColor.menubar
        case .monitor: return CFinderTheme.FeatureColor.monitor
        case .network: return CFinderTheme.FeatureColor.network
        }
    }
}

public struct DashboardView: View {
    public static let switchTabNotification = Notification.Name("SFinderSwitchDashboardTab")
    
    @State private var selectedTab: DashboardTab
    @State private var ambientGlow: Bool = false
    
    // Live permissions state
    @State private var screenCaptureGranted: Bool = PermissionsManager.shared.isScreenCaptureGranted
    @State private var accessibilityGranted: Bool = PermissionsManager.shared.isAccessibilityGranted
    @State private var finderExtensionEnabled: Bool = PermissionsManager.shared.isFinderExtensionEnabled
    @State private var launchAtLoginEnabled: Bool = PermissionsManager.shared.isLaunchAtLoginEnabled
    
    // OCR settings state
    @State private var currentPresetDisplay: String = ScreenOCREngine.shared.currentPreset.displayShortcut
    @State private var ignoreLineBreaks: Bool = ScreenOCREngine.shared.ignoreLineBreaks
    @State private var tableDetection: Bool = ScreenOCREngine.shared.tableDetection
    @State private var autoOpenURL: Bool = ScreenOCREngine.shared.autoOpenURL
    @State private var detectQR: Bool = ScreenOCREngine.shared.detectQR
    @State private var playSound: Bool = ScreenOCREngine.shared.playSound
    
    // Power state
    @ObservedObject private var power = PowerManager.shared
    
    // Screen Recording Settings
    @AppStorage("sfinder_record_fps") private var recordFPS: Int = 60
    @AppStorage("sfinder_record_resolution") private var recordResolution: String = "Retina Native"
    @AppStorage("sfinder_record_sys_audio") private var recordSystemAudio: Bool = true
    @AppStorage("sfinder_record_mic") private var recordMicrophone: Bool = false
    @AppStorage("sfinder_record_click_effects") private var showClickEffects: Bool = true
    @AppStorage("sfinder_record_keystrokes") private var showKeystrokes: Bool = true
    
    // General Settings
    @AppStorage("sfinder_play_sound_effects") private var playGeneralSounds: Bool = true
    @AppStorage("sfinder_auto_clean_rename_list") private var autoCleanRenameList: Bool = true
    
    public init(initialTab: DashboardTab = .overview) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    private var healthScore: Int {
        var count = 0
        if screenCaptureGranted { count += 1 }
        if accessibilityGranted { count += 1 }
        if finderExtensionEnabled { count += 1 }
        return count
    }
    
    public var body: some View {
        ZStack {
            // Native Apple Liquid Glass Background
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()
            
            // Living Minimal Ambient Glow (Ultra Subtle)
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(ambientGlow ? 0.025 : 0.012))
                        .frame(width: 440, height: 440)
                        .blur(radius: 90)
                        .offset(x: proxy.size.width * 0.45, y: -proxy.size.height * 0.15)
                    
                    Circle()
                        .fill(Color(hex: "38BDF8").opacity(ambientGlow ? 0.02 : 0.01))
                        .frame(width: 380, height: 380)
                        .blur(radius: 90)
                        .offset(x: -proxy.size.width * 0.1, y: proxy.size.height * 0.4)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: ambientGlow)
            
            // Main Content Layout
            HStack(spacing: 0) {
                // Left Sidebar
                DashboardSidebarView(
                    selectedTab: $selectedTab,
                    healthScore: healthScore,
                    currentPresetDisplay: currentPresetDisplay,
                    isPowerActive: power.isActive
                )
                .frame(width: 255)
                .background(Color.black.opacity(0.18))
                
                // Fine Glass Border Separator
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.04), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
                
                // Right Detail View
                VStack(spacing: 0) {
                    DashboardHeaderBar(
                        selectedTab: selectedTab,
                        currentPresetDisplay: currentPresetDisplay,
                        isPowerActive: power.isActive,
                        onRefresh: refreshAllStatuses
                    )
                    
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        tabContent
                            .padding(26)
                            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedTab)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.08))
            }
        }
        .frame(width: 960, height: 650)
        .onAppear {
            ambientGlow = true
            refreshAllStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAllStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: PermissionsManager.permissionsDidChangeNotification)) { _ in
            refreshAllStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: DashboardView.switchTabNotification)) { notif in
            if let tab = notif.object as? DashboardTab {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    selectedTab = tab
                }
            }
        }
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            OverviewTabContentView(
                healthScore: healthScore,
                currentPresetDisplay: currentPresetDisplay,
                isPowerActive: power.isActive,
                powerTimeRemaining: power.formattedRemainingTime,
                screenCaptureGranted: screenCaptureGranted,
                accessibilityGranted: accessibilityGranted,
                finderExtensionEnabled: finderExtensionEnabled,
                onSelectTab: { selectedTab = $0 },
                onRefresh: refreshAllStatuses
            )
        case .permissions:
            PermissionsTabContentView(
                healthScore: healthScore,
                screenCaptureGranted: screenCaptureGranted,
                accessibilityGranted: accessibilityGranted,
                finderExtensionEnabled: finderExtensionEnabled,
                launchAtLoginEnabled: launchAtLoginEnabled,
                onRefresh: refreshAllStatuses
            )
        case .ocr:
            OCRTabContentView(
                currentPresetDisplay: $currentPresetDisplay,
                ignoreLineBreaks: $ignoreLineBreaks,
                tableDetection: $tableDetection,
                autoOpenURL: $autoOpenURL,
                detectQR: $detectQR,
                playSound: $playSound
            )
        case .recorder:
            RecorderTabContentView(
                recordFPS: $recordFPS,
                recordSystemAudio: $recordSystemAudio,
                recordMicrophone: $recordMicrophone,
                showClickEffects: $showClickEffects,
                showKeystrokes: $showKeystrokes
            )
        case .wake:
            WakeTabContentView(
                isPowerActive: power.isActive,
                powerTimeRemaining: power.formattedRemainingTime,
                allowDisplaySleep: $power.allowDisplaySleep,
                stopOnLowBattery: $power.stopOnLowBattery,
                onRefresh: refreshAllStatuses
            )
        case .rename:
            RenameTabContentView(
                autoCleanRenameList: $autoCleanRenameList
            )
        case .notes:
            NotesTabContentView()
        case .snap:
            SnapTabContentView()
        case .menubar:
            MenuBarIconsTabContentView()
        case .monitor:
            SystemMonitorTabContentView()
        case .network:
            NetworkTabContentView()
        case .general:
            GeneralTabContentView(
                launchAtLoginEnabled: $launchAtLoginEnabled,
                playGeneralSounds: $playGeneralSounds,
                onRefresh: refreshAllStatuses
            )
        }
    }
    
    private func refreshAllStatuses() {
        screenCaptureGranted = PermissionsManager.shared.isScreenCaptureGranted
        accessibilityGranted = PermissionsManager.shared.isAccessibilityGranted
        finderExtensionEnabled = PermissionsManager.shared.isFinderExtensionEnabled
        launchAtLoginEnabled = PermissionsManager.shared.isLaunchAtLoginEnabled
        
        currentPresetDisplay = ScreenOCREngine.shared.currentPreset.displayShortcut
        ignoreLineBreaks = ScreenOCREngine.shared.ignoreLineBreaks
        tableDetection = ScreenOCREngine.shared.tableDetection
        autoOpenURL = ScreenOCREngine.shared.autoOpenURL
        detectQR = ScreenOCREngine.shared.detectQR
        playSound = ScreenOCREngine.shared.playSound
    }
}

// MARK: - Sidebar View Component

struct DashboardSidebarView: View {
    @Binding var selectedTab: DashboardTab
    let healthScore: Int
    let currentPresetDisplay: String
    let isPowerActive: Bool
    @ObservedObject private var monitor = SystemMonitorEngine.shared
    @ObservedObject private var netMonitor = NetworkMonitorEngine.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic Light Safe Area
            Spacer().frame(height: 38)
            
            // Minimal Brand Header
            HStack(spacing: 11) {
                Image(nsImage: BrandAssets.appIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                
                Text("CFinder")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            
            // Minimal System Readiness Indicator
            Button(action: { selectedTab = .permissions }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(healthScore == 3 ? Color(hex: "10B981") : Color.orange)
                        .frame(width: 7, height: 7)
                    
                    Text(healthScore == 3 ? "Hệ thống sẵn sàng" : "\(healthScore)/3 Quyền bảo mật")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.25))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
                .padding(.horizontal, 16)
            
            // Navigation Groups
            VStack(alignment: .leading, spacing: 14) {
                // Group 1: Hệ thống
                VStack(alignment: .leading, spacing: 2) {
                    Text("HỆ THỐNG")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 2)
                    
                    SidebarItemButton(tab: .overview, selectedTab: $selectedTab, badge: nil)
                    SidebarItemButton(tab: .permissions, selectedTab: $selectedTab, badge: healthScore == 3 ? nil : "\(healthScore)/3")
                    SidebarItemButton(tab: .general, selectedTab: $selectedTab, badge: nil)
                }
                
                // Group 2: Công cụ
                VStack(alignment: .leading, spacing: 2) {
                    Text("BỘ CÔNG CỤ")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 2)
                    
                    SidebarItemButton(tab: .ocr, selectedTab: $selectedTab, badge: currentPresetDisplay)
                    SidebarItemButton(tab: .recorder, selectedTab: $selectedTab, badge: "⌥R")
                    SidebarItemButton(tab: .wake, selectedTab: $selectedTab, badge: isPowerActive ? "Đang bật" : nil)
                    SidebarItemButton(tab: .rename, selectedTab: $selectedTab, badge: "⌘⇧R")
                    SidebarItemButton(tab: .notes, selectedTab: $selectedTab, badge: "⌥N")
                    SidebarItemButton(tab: .snap, selectedTab: $selectedTab, badge: "⌃⌥")
                    SidebarItemButton(tab: .menubar, selectedTab: $selectedTab, badge: "⌃⌥B")
                    SidebarItemButton(tab: .monitor, selectedTab: $selectedTab, badge: "\(Int(monitor.snapshot.cpu.totalUsage))%")
                    SidebarItemButton(tab: .network, selectedTab: $selectedTab, badge: netMonitor.throughput.downloadBytesPerSec > 1024 ? netMonitor.throughput.formattedDownloadSpeed : (netMonitor.interfaceInfo.isConnected ? "●" : nil))
                }
            }
            .padding(.vertical, 10)
            
            Spacer()
        }
    }
}

// MARK: - Header Bar Component

struct DashboardHeaderBar: View {
    let selectedTab: DashboardTab
    let currentPresetDisplay: String
    let isPowerActive: Bool
    let onRefresh: () -> Void
    
    private var cleanHeaderTitle: String {
        switch selectedTab {
        case .overview: return "Tổng quan"
        case .permissions: return "Quyền hệ thống"
        case .general: return "Cài đặt chung"
        case .ocr: return "Quét chữ OCR"
        case .recorder: return "Ghi màn hình"
        case .wake: return "Chống ngủ Mac"
        case .rename: return "Đổi tên tệp Finder"
        case .notes: return "Ghi chú mép màn hình (Edge Notes)"
        case .snap: return "Snap Areas (Chia & Bố cục cửa sổ)"
        case .menubar: return "Menu Bar Icons (Ẩn bớt biểu tượng thanh menu)"
        case .monitor: return "Theo dõi hệ thống (CPU, GPU, RAM & Nhiệt độ)"
        case .network: return "Mạng (Tốc độ thời gian thực & Đo kết nối Internet)"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selectedTab.accentColor.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(selectedTab.accentColor.opacity(0.28), lineWidth: 1)
                    )
                
                Image(systemName: selectedTab.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(selectedTab.accentColor)
            }
            
            Text(cleanHeaderTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Header Quick Action Button
            switch selectedTab {
            case .ocr:
                Button(action: {
                    Task { _ = try? await ScreenOCREngine.shared.captureScreenInteractively() }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                        Text("Quét ngay (\(currentPresetDisplay))")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5.5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            case .recorder:
                HStack(spacing: 6) {
                    Circle().fill(Color.white.opacity(0.6)).frame(width: 6, height: 6)
                    Text("Phím tắt ⌥R")
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.05)))
            case .wake:
                Button(action: {
                    PowerManager.shared.toggleQuickSession()
                    onRefresh()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isPowerActive ? "stop.fill" : "bolt.fill")
                        Text(isPowerActive ? "Dừng giữ thức" : "Bật thức nhanh (⌘I)")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(isPowerActive ? Color(hex: "DC2626") : .white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5.5)
                    .background(
                        Capsule()
                            .fill(isPowerActive ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isPowerActive ? Color(hex: "DC2626").opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            case .rename:
                Button(action: {
                    HostActionCoordinator.shared.presentBatchRename(urls: [])
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil.and.list.clipboard")
                        Text("Mở Studio Đổi tên")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5.5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            default:
                EmptyView()
            }
            
            // Refresh Button
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(7)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.04))
                            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Cập nhật lại trạng thái")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.015))
    }
}

// MARK: - Overview Tab Content

struct OverviewTabContentView: View {
    @ObservedObject private var recorder = ScreenRecorderEngine.shared
    let healthScore: Int
    let currentPresetDisplay: String
    let isPowerActive: Bool
    let powerTimeRemaining: String
    let screenCaptureGranted: Bool
    let accessibilityGranted: Bool
    let finderExtensionEnabled: Bool
    let onSelectTab: (DashboardTab) -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 22) {
            if healthScore < 3 {
                permissionBannerSection
            }
            toolGridSection
            permissionsSnapshotSection
        }
    }
    
    private var permissionBannerSection: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "F59E0B"))
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Cần kích hoạt thêm quyền macOS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text("Còn \(3 - healthScore) quyền hệ thống chưa được kích hoạt. Cấp quyền để mở khóa toàn bộ công cụ.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.65))
            }
            
            Spacer()
            
            Button("Cấp quyền ngay") {
                onSelectTab(.permissions)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "F59E0B").opacity(0.4), lineWidth: 1)
                    )
            )
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "F59E0B").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(hex: "F59E0B").opacity(0.20), lineWidth: 1)
                )
        )
    }
    
    private var toolGridSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CÔNG CỤ NỔI BẬT")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                LiquidToolCard(
                    title: "Quét chữ OCR",
                    subtitle: "Nhận diện văn bản trên màn hình và trích bảng",
                    icon: "text.viewfinder",
                    accentColor: CFinderTheme.FeatureColor.ocr,
                    statusBadge: currentPresetDisplay,
                    actionLabel: "Quét ngay"
                ) {
                    Task { _ = try? await ScreenOCREngine.shared.captureScreenInteractively() }
                } onConfigure: {
                    onSelectTab(.ocr)
                }
                
                LiquidToolCard(
                    title: "Ghi màn hình",
                    subtitle: recorder.isRecording ? "Đang ghi video (\(recorder.formattedDuration)). Nhấn để dừng và lưu." : "Quay 60/120fps Retina, thu âm thanh & mic",
                    icon: "record.circle.fill",
                    accentColor: recorder.isRecording ? Color(hex: "EF4444") : CFinderTheme.FeatureColor.recorder,
                    statusBadge: recorder.isRecording ? "Đang ghi" : "⌥R",
                    actionLabel: recorder.isRecording ? "Dừng quay" : "Ghi ngay"
                ) {
                    ScreenRecorderEngine.shared.toggleRecording()
                } onConfigure: {
                    onSelectTab(.recorder)
                }
                
                LiquidToolCard(
                    title: "Chống ngủ Mac",
                    subtitle: isPowerActive ? "Đang giữ thức (\(powerTimeRemaining))" : "Ngăn máy ngủ khi tải file, render đồ hoạ",
                    icon: isPowerActive ? "bolt.fill" : "bolt.slash",
                    accentColor: CFinderTheme.FeatureColor.wake,
                    statusBadge: isPowerActive ? "Đang chạy" : "Tắt",
                    actionLabel: isPowerActive ? "Dừng thức" : "Bật thức"
                ) {
                    PowerManager.shared.toggleQuickSession()
                    onRefresh()
                } onConfigure: {
                    onSelectTab(.wake)
                }
                
                LiquidToolCard(
                    title: "Đổi tên tệp Finder",
                    subtitle: "Đánh số, thêm chữ, hoàn tác an toàn ⌘Z",
                    icon: "pencil.and.list.clipboard",
                    accentColor: CFinderTheme.FeatureColor.rename,
                    statusBadge: "⌘⇧R",
                    actionLabel: "Mở công cụ"
                ) {
                    HostActionCoordinator.shared.presentBatchRename(urls: [])
                } onConfigure: {
                    onSelectTab(.rename)
                }
                
                LiquidToolCard(
                    title: "Ghi chú mép màn hình",
                    subtitle: "Rê chuột mép phải là mở, gõ tự lưu, đồng bộ  Notes",
                    icon: "note.text",
                    accentColor: CFinderTheme.FeatureColor.notes,
                    statusBadge: "⌥N",
                    actionLabel: "Mở ghi chú"
                ) {
                    EdgeNotesWindowController.shared.toggleDrawer()
                } onConfigure: {
                    onSelectTab(.notes)
                }
                
                LiquidToolCard(
                    title: "Snap Areas",
                    subtitle: "Kéo mép & góc chia đôi, chia tư màn hình",
                    icon: "rectangle.split.2x2",
                    accentColor: CFinderTheme.FeatureColor.snap,
                    statusBadge: "⌃⌥",
                    actionLabel: "Bố cục cửa sổ"
                ) {
                    onSelectTab(.snap)
                } onConfigure: {
                    onSelectTab(.snap)
                }
                
                LiquidToolCard(
                    title: "Lọc video trùng (VideoTwin)",
                    subtitle: "Tìm & dọn video trùng lặp theo nội dung khung hình",
                    icon: "film.stack",
                    accentColor: CFinderTheme.FeatureColor.videoTwin,
                    statusBadge: "Studio",
                    actionLabel: "Mở VideoTwin"
                ) {
                    HostActionCoordinator.shared.presentVideoTwinStudio(urls: [])
                } onConfigure: {
                    HostActionCoordinator.shared.presentVideoTwinStudio(urls: [])
                }
                
                LiquidToolCard(
                    title: "So sánh & Chấm điểm Video",
                    subtitle: "So sánh bitrate, độ phân giải và chất lượng song song",
                    icon: "rectangle.split.2x1.fill",
                    accentColor: CFinderTheme.FeatureColor.videoInspector,
                    statusBadge: "So sánh",
                    actionLabel: "Mở So sánh"
                ) {
                    HostActionCoordinator.shared.presentVideoInspector(urls: [])
                } onConfigure: {
                    HostActionCoordinator.shared.presentVideoInspector(urls: [])
                }
                
                LiquidToolCard(
                    title: "Cắt & Dán Finder",
                    subtitle: "Cắt file ⌘X như Windows, dán ⌘V di chuyển",
                    icon: "scissors",
                    accentColor: CFinderTheme.FeatureColor.cutPaste,
                    statusBadge: "⌘X / ⌘V",
                    actionLabel: "Đang kích hoạt"
                ) {
                    onSelectTab(.general)
                } onConfigure: {
                    onSelectTab(.general)
                }
                
                LiquidToolCard(
                    title: "Chụp ảnh cuộn",
                    subtitle: "Tự cuộn hoặc cuộn tay, ghép ảnh dài liền mạch",
                    icon: "arrow.up.and.down.and.sparkles",
                    accentColor: CFinderTheme.FeatureColor.scrollCapture,
                    statusBadge: "⌥S",
                    actionLabel: "Chụp ngay"
                ) {
                    HostActionCoordinator.shared.presentScrollingCapture()
                } onConfigure: {
                    HostActionCoordinator.shared.presentScrollingCapture()
                }
                
                LiquidToolCard(
                    title: "Lịch sử quét OCR",
                    subtitle: "Xem lại và sao chép các đoạn văn bản đã quét",
                    icon: "clock.arrow.circlepath",
                    accentColor: CFinderTheme.FeatureColor.ocr,
                    statusBadge: "Lịch sử",
                    actionLabel: "Mở lịch sử"
                ) {
                    HostActionCoordinator.shared.presentOCRHistory()
                } onConfigure: {
                    HostActionCoordinator.shared.presentOCRHistory()
                }
                
                LiquidToolCard(
                    title: "Menu Bar Icons",
                    subtitle: "Ẩn bớt icon thanh menu, tự ẩn lại sau khi dùng",
                    icon: "menubar.rectangle",
                    accentColor: CFinderTheme.primaryLight,
                    statusBadge: "⌃⌥B",
                    actionLabel: "Quản lý icon"
                ) {
                    onSelectTab(.menubar)
                } onConfigure: {
                    onSelectTab(.menubar)
                }
                
                LiquidToolCard(
                    title: "Theo dõi hệ thống",
                    subtitle: "Nhiệt độ CPU/GPU, mức dùng RAM & áp lực bộ nhớ",
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    accentColor: .white.opacity(0.85),
                    statusBadge: "Giám sát",
                    actionLabel: "Xem thông số"
                ) {
                    onSelectTab(.monitor)
                } onConfigure: {
                    onSelectTab(.monitor)
                }
                
                LiquidToolCard(
                    title: "Mạng & Tốc độ",
                    subtitle: "Tốc độ mạng hiện tại, lưu lượng trực tiếp & đo tốc độ",
                    icon: "network",
                    accentColor: .white.opacity(0.85),
                    statusBadge: "Trực tuyến",
                    actionLabel: "Đo tốc độ"
                ) {
                    onSelectTab(.network)
                } onConfigure: {
                    onSelectTab(.network)
                }
            }
        }
    }
    
    private var permissionsSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("QUYỀN HỆ THỐNG")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Button("Chi tiết >") {
                    onSelectTab(.permissions)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .buttonStyle(.plain)
            }
            
            if healthScore == 3 {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "10B981"))
                    
                    Text("Tất cả quyền bảo mật macOS đã được kích hoạt đầy đủ (3/3)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("Sẵn sàng")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Color(hex: "10B981"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: "10B981").opacity(0.12)))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            } else {
                VStack(spacing: 8) {
                    PermissionRowView(
                        type: .screenCapture,
                        isGranted: screenCaptureGranted,
                        onRequest: {
                            PermissionsManager.shared.requestScreenCapture()
                            onRefresh()
                        }
                    )
                    
                    PermissionRowView(
                        type: .accessibility,
                        isGranted: accessibilityGranted,
                        onRequest: {
                            PermissionsManager.shared.requestAccessibility()
                            onRefresh()
                        }
                    )
                    
                    PermissionRowView(
                        type: .finderSync,
                        isGranted: finderExtensionEnabled,
                        onRequest: {
                            PermissionsManager.shared.enableFinderExtension()
                            onRefresh()
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Permissions Tab Content

struct PermissionsTabContentView: View {
    let healthScore: Int
    let screenCaptureGranted: Bool
    let accessibilityGranted: Bool
    let finderExtensionEnabled: Bool
    let launchAtLoginEnabled: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Health Score Ring Card
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 7)
                        .frame(width: 62, height: 62)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(healthScore) / 3.0)
                        .stroke(
                            healthScore == 3 ? Color.green : Color.orange,
                            style: StrokeStyle(lineWidth: 7, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 62, height: 62)
                    
                    Text("\(healthScore)/3")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(healthScore == 3 ? "Tất cả các quyền hệ thống đã kích hoạt hoàn tất!" : "Cần cấp thêm quyền bảo mật để chạy trơn tru")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("macOS yêu cầu người dùng xác nhận các quyền Ghi màn hình (Vision OCR), Trợ năng (Phím tắt) và Tiện ích mở rộng Finder.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.68))
                }
                
                Spacer()
                
                Button("Kiểm tra lại") {
                    onRefresh()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            
            // Detailed Permission Cards
            VStack(alignment: .leading, spacing: 12) {
                Text("DANH SÁCH QUYỀN HỆ THỐNG")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.45))
                
                VStack(spacing: 12) {
                    DetailedPermissionCard(
                        title: "Quyền Ghi màn hình (Screen Recording)",
                        description: "Cần thiết để engine Apple Vision chụp ảnh màn hình nhận diện chữ OCR và tính năng Quay màn hình.",
                        icon: "display.trianglebadge.exclamationmark",
                        isGranted: screenCaptureGranted,
                        buttonTitle: screenCaptureGranted ? "Đã cấp ✓" : "Cấp quyền Ghi màn hình"
                    ) {
                        PermissionsManager.shared.requestScreenCapture()
                        onRefresh()
                    }
                    
                    DetailedPermissionCard(
                        title: "Quyền Trợ năng (Accessibility)",
                        description: "Cho phép bắt phím tắt toàn cục (⌥C, ⌥R, ⌘I) ngay cả khi đang dùng ứng dụng khác.",
                        icon: "figure.roll",
                        isGranted: accessibilityGranted,
                        buttonTitle: accessibilityGranted ? "Đã cấp ✓" : "Cấp quyền Trợ năng"
                    ) {
                        PermissionsManager.shared.requestAccessibility()
                        onRefresh()
                    }
                    
                    DetailedPermissionCard(
                        title: "Tiện ích mở rộng Finder (Finder Sync Extension)",
                        description: "Tích hợp menu ngữ cảnh chuột phải và icon trạng thái trực tiếp trong macOS Finder.",
                        icon: "folder.badge.gearshape",
                        isGranted: finderExtensionEnabled,
                        buttonTitle: finderExtensionEnabled ? "Đã kích hoạt ✓" : "Kích hoạt Finder Sync"
                    ) {
                        PermissionsManager.shared.enableFinderExtension()
                        onRefresh()
                    }
                    
                    DetailedPermissionCard(
                        title: "Khởi động cùng máy (Launch at Login)",
                        description: "Tự động chạy CFinder ở Menu Bar khi khởi động máy Mac để các phím tắt luôn sẵn sàng.",
                        icon: "power",
                        isGranted: launchAtLoginEnabled,
                        buttonTitle: launchAtLoginEnabled ? "Đang bật ✓" : "Bật tự khởi động"
                    ) {
                        PermissionsManager.shared.toggleLaunchAtLogin(enabled: !launchAtLoginEnabled)
                        onRefresh()
                    }
                }
            }
        }
    }
}

// MARK: - OCR Tab Content

struct OCRTabContentView: View {
    @Binding var currentPresetDisplay: String
    @Binding var ignoreLineBreaks: Bool
    @Binding var tableDetection: Bool
    @Binding var autoOpenURL: Bool
    @Binding var detectQR: Bool
    @Binding var playSound: Bool
    
    @State private var isRecordingShortcut: Bool = false
    @State private var keyMonitor: Any?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            shortcutSection
            togglesSection
            actionsSection
        }
        .onDisappear {
            stopRecordingMonitor()
        }
    }
    
    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHÍM TẮT TOÀN CỤC QUÉT MÀN HÌNH")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white.opacity(0.45))
            
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Phím kích hoạt nhanh:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Bấm nút bên phải rồi gõ tổ hợp phím mới trên bàn phím để gán lại.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                ShortcutRecordButton(
                    isRecording: isRecordingShortcut,
                    currentPresetDisplay: currentPresetDisplay
                ) {
                    if isRecordingShortcut {
                        stopRecordingMonitor()
                    } else {
                        startRecordingMonitor()
                    }
                }
                
                Button("Mặc định (⌥C)") {
                    ScreenOCREngine.shared.resetToDefaultHotKey()
                    currentPresetDisplay = "⌥C"
                }
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.7))
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
    }
    
    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHẾ ĐỘ QUÉT & NHẬN DIỆN THÔNG MINH")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white.opacity(0.45))
            
            VStack(spacing: 0) {
                LiquidGlassToggleRow(
                    title: "Bỏ qua ngắt dòng (Gộp đoạn văn)",
                    subtitle: "Tự động gộp các dòng xuống hàng thành một đoạn văn liền mạch",
                    icon: "text.alignleft",
                    isOn: $ignoreLineBreaks
                ) { val in
                    ScreenOCREngine.shared.ignoreLineBreaks = val
                }
                
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Nhận diện bảng biểu (Table -> TSV)",
                    subtitle: "Tự động căn chỉnh cột và phân cách bằng Tab để dán trực tiếp vào Excel / Numbers / Google Sheets",
                    icon: "tablecells",
                    isOn: $tableDetection
                ) { val in
                    ScreenOCREngine.shared.tableDetection = val
                }
                
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Tự động mở link nếu là URL web",
                    subtitle: "Nếu văn bản quét được là đường link (http/https), tự động mở trình duyệt web",
                    icon: "safari",
                    isOn: $autoOpenURL
                ) { val in
                    ScreenOCREngine.shared.autoOpenURL = val
                }
                
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Nhận diện mã QR Code & Barcode",
                    subtitle: "Tự động quét và giải mã nội dung từ QR code cùng lúc với nhận diện chữ",
                    icon: "qrcode",
                    isOn: $detectQR
                ) { val in
                    ScreenOCREngine.shared.detectQR = val
                }
                
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Âm thanh máy ảnh khi chụp thành công",
                    subtitle: "Phát âm thanh shutter nhẹ nhàng để xác nhận việc sao chép vào Clipboard",
                    icon: "speaker.wave.2.fill",
                    isOn: $playSound
                ) { val in
                    ScreenOCREngine.shared.playSound = val
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
    }
    
    private var actionsSection: some View {
        HStack(spacing: 14) {
            Button(action: {
                HostActionCoordinator.shared.presentOCRHistory()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Mở Lịch sử Quét Studio")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            
            Button(action: {
                Task { _ = try? await ScreenOCREngine.shared.captureMultiRegionInteractively() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.badge.plus")
                    Text("Quét nhiều vùng liên tiếp (Multi-Region)")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
    
    private func startRecordingMonitor() {
        isRecordingShortcut = true
        stopRecordingMonitor()
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                self.stopRecordingMonitor()
                return nil
            }
            
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            var carbonMods: UInt32 = 0
            var displayParts: [String] = []
            
            if flags.contains(.control) {
                carbonMods |= UInt32(controlKey)
                displayParts.append("⌃")
            }
            if flags.contains(.option) {
                carbonMods |= UInt32(optionKey)
                displayParts.append("⌥")
            }
            if flags.contains(.shift) {
                carbonMods |= UInt32(shiftKey)
                displayParts.append("⇧")
            }
            if flags.contains(.command) {
                carbonMods |= UInt32(cmdKey)
                displayParts.append("⌘")
            }
            
            let keyStr = keyStringForCode(event.keyCode)
            displayParts.append(keyStr)
            let fullDisplay = displayParts.joined()
            
            ScreenOCREngine.shared.setCustomHotKey(
                keyCode: UInt32(event.keyCode),
                modifiers: carbonMods,
                display: fullDisplay
            )
            self.currentPresetDisplay = fullDisplay
            self.stopRecordingMonitor()
            return nil
        }
    }
    
    private func stopRecordingMonitor() {
        isRecordingShortcut = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func keyStringForCode(_ code: UInt16) -> String {
        switch code {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 45: return "N"
        case 46: return "M"
        case 49: return "Space"
        default: return "Key\(code)"
        }
    }
}

// MARK: - Recorder Tab Content

struct RecorderTabContentView: View {
    @ObservedObject private var recorder = ScreenRecorderEngine.shared
    @Binding var recordFPS: Int
    @Binding var recordSystemAudio: Bool
    @Binding var recordMicrophone: Bool
    @Binding var showClickEffects: Bool
    @Binding var showKeystrokes: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            bannerSection
            optionsSection
        }
    }
    
    private var bannerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FB7185").opacity(0.14))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: "FB7185"))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Bộ máy Quay Màn Hình ScreenCaptureKit")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("60 / 120 FPS")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                
                Text("Tận dụng phần cứng Apple Silicon VideoToolbox mã hóa zero-copy: siêu mượt, không nóng máy, tiết kiệm pin tối đa.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.65))
            }
            
            Spacer()
            
            Button(action: {
                ScreenRecorderEngine.shared.toggleRecording()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.system(size: 13))
                    Text(recorder.isRecording ? "Dừng ghi (\(recorder.formattedDuration))" : "Bắt đầu ghi (⌥R)")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(recorder.isRecording ? Color(hex: "EF4444") : CFinderTheme.primary)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CẤU HÌNH HÌNH ẢNH & ÂM THANH")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white.opacity(0.45))
            
            VStack(spacing: 0) {
                // Frame rate picker row
                HStack {
                    Image(systemName: "speedometer")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tốc độ khung hình (Frame Rate)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Hỗ trợ ProMotion 120fps trên MacBook Pro và 60fps chuẩn")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $recordFPS) {
                        Text("30 FPS (Tiết kiệm)").tag(30)
                        Text("60 FPS (Mượt mà)").tag(60)
                        Text("120 FPS (ProMotion)").tag(120)
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                .padding(16)
                
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Thu âm thanh máy tính (System Audio)",
                    subtitle: "Ghi lại âm thanh phát ra từ loa/tai nghe máy Mac trực tiếp 100% không cần driver ảo",
                    icon: "speaker.wave.3.fill",
                    isOn: $recordSystemAudio
                ) { _ in }
                
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Thu âm Microphone của bạn",
                    subtitle: "Thu tiếng nói trực tiếp từ Micro kèm lọc ồn và chuẩn hóa âm lượng",
                    icon: "mic.fill",
                    isOn: $recordMicrophone
                ) { _ in }
                
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Hiệu ứng gợn sóng khi nhấp chuột (Click Ripple)",
                    subtitle: "Vẽ vòng tròn lan tỏa khi nhấp chuột trái hoặc chuột phải trong video",
                    icon: "cursorarrow.rays",
                    isOn: $showClickEffects
                ) { _ in }
                
                Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Hiển thị phím bấm khi gõ (Keystroke Overlay)",
                    subtitle: "Tự động hiển thị các phím tắt (⌘C, ⌥V...) nổi trên màn hình khi bạn gõ",
                    icon: "keyboard.fill",
                    isOn: $showKeystrokes
                ) { _ in }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
        }
    }
}

// MARK: - Wake Tab Content

struct WakeTabContentView: View {
    let isPowerActive: Bool
    let powerTimeRemaining: String
    @Binding var allowDisplaySleep: Bool
    @Binding var stopOnLowBattery: Bool
    let onRefresh: () -> Void
    @ObservedObject private var power = PowerManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Live Status Card (Master Switch & Duration Presets)
            masterWakeStatusCard
            
            // Dedicated Sleep Timer Card (Hẹn giờ ngủ máy ban đêm)
            SleepTimerCard()
            
            // Smart Network Trigger Section (Auto Sleep/Shutdown on Download Complete)
            SmartNetworkTriggerCard()
            
            // Power Toggles
            optionsSection
        }
    }
    
    private var masterWakeStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isPowerActive ? Color(hex: "F59E0B").opacity(0.15) : Color.white.opacity(0.06))
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: isPowerActive ? "bolt.fill" : "moon.zzz.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isPowerActive ? Color(hex: "F59E0B") : .white.opacity(0.55))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isPowerActive ? "Đang giữ thức máy Mac" : "Chế độ ngủ tự nhiên (macOS)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Circle()
                            .fill(isPowerActive ? Color(hex: "F59E0B") : Color.white.opacity(0.2))
                            .frame(width: 7, height: 7)
                    }
                    
                    Text(isPowerActive ? "Thời gian giữ thức: \(powerTimeRemaining) • CPU không bị tạm dừng" : "Máy Mac sẽ tự động ngủ theo thiết lập tiết kiệm năng lượng của hệ thống")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        PowerManager.shared.toggleQuickSession()
                        onRefresh()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isPowerActive ? "stop.fill" : "play.fill")
                            .font(.system(size: 10))
                        Text(isPowerActive ? "Dừng giữ thức (⌘X)" : "Bật giữ thức (⌘I)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(isPowerActive ? Color(hex: "EF4444") : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isPowerActive ? Color.red.opacity(0.12) : Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(isPowerActive ? Color.red.opacity(0.3) : Color.white.opacity(0.16), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            
            Divider().background(Color.white.opacity(0.05))
            
            // Quick Duration Preset Buttons
            VStack(alignment: .leading, spacing: 6) {
                Text("KHOẢNG THỜI GIAN GIỮ THỨC THIẾT THỰC")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                
                HStack(spacing: 8) {
                    presetButton(title: "∞ Vô hạn", minutes: 0)
                    presetButton(title: "15 phút", minutes: 15)
                    presetButton(title: "30 phút", minutes: 30)
                    presetButton(title: "1 giờ", minutes: 60)
                    presetButton(title: "2 giờ", minutes: 120)
                    presetButton(title: "4 giờ", minutes: 240)
                    workdayEndButton
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(isPowerActive ? 0.05 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isPowerActive ? Color(hex: "F59E0B").opacity(0.25) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private func presetButton(title: String, minutes: Int) -> some View {
        let isSelected = isPowerActive && (
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
                onRefresh()
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color(hex: "F59E0B").opacity(0.85) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    private var workdayEndButton: some View {
        Button(action: {
            let cal = Calendar.current
            let now = Date()
            var comp = cal.dateComponents([.year, .month, .day], from: now)
            comp.hour = 18
            comp.minute = 0
            if let target = cal.date(from: comp), target > now {
                let diff = target.timeIntervalSince(now)
                let mins = max(1, Int(round(diff / 60)))
                withAnimation {
                    power.startTimedSession(minutes: mins)
                    onRefresh()
                }
            } else {
                withAnimation {
                    power.startTimedSession(hours: 4)
                    onRefresh()
                }
            }
        }) {
            Text("Đến 18:00")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .help("Giữ thức cho đến hết giờ làm việc (18:00 chiều)")
    }
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TUỲ CHỌN GIỮ NGUỒN")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            VStack(spacing: 0) {
                LiquidGlassToggleRow(
                    title: "Cho phép màn hình tắt ngủ (Display Sleep)",
                    subtitle: "Màn hình tắt tiết kiệm pin nhưng CPU vẫn giữ thức để render hoặc tải tệp",
                    icon: "display",
                    accentColor: .white.opacity(0.85),
                    isOn: $allowDisplaySleep
                ) { val in
                    PowerManager.shared.allowDisplaySleep = val
                }
                
                Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
                
                LiquidGlassToggleRow(
                    title: "Tự ngắt giữ thức khi pin máy yếu (<10%)",
                    subtitle: "Tự động tắt chống ngủ để bảo vệ pin máy khi dung lượng sắp cạn",
                    icon: "battery.25",
                    accentColor: .white.opacity(0.85),
                    isOn: $stopOnLowBattery
                ) { val in
                    PowerManager.shared.stopOnLowBattery = val
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
            )
        }
    }
}

// MARK: - Sleep Timer Card (Hẹn giờ tự động ngủ máy ban đêm)

struct SleepTimerCard: View {
    @ObservedObject private var power = PowerManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "A855F7").opacity(0.12))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "C084FC"))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Hẹn giờ tự động ngủ máy (Sleep Timer)")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        if power.isSleepTimerActive {
                            Circle()
                                .fill(Color(hex: "A855F7"))
                                .frame(width: 7, height: 7)
                        }
                    }
                    
                    Text(power.isSleepTimerActive ? "Sẽ \(power.sleepTimerAction.title.lowercased()) sau: \(power.formattedSleepTimerRemaining)" : "Tự động đưa máy vào giấc ngủ sâu khi nghe nhạc, xem phim hoặc render ban đêm")
                        .font(.system(size: 11))
                        .foregroundColor(power.isSleepTimerActive ? Color(hex: "C084FC") : .white.opacity(0.55))
                }
                
                Spacer()
                
                if power.isSleepTimerActive {
                    Button(action: {
                        withAnimation {
                            power.cancelSleepTimer()
                        }
                    }) {
                        Text("Huỷ hẹn giờ")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color(hex: "EF4444"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: "EF4444").opacity(0.12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color(hex: "EF4444").opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider().background(Color.white.opacity(0.05))
            
            // Preset Buttons Row
            VStack(alignment: .leading, spacing: 6) {
                Text("HẸN GIỜ NGỦ SAU")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                
                HStack(spacing: 8) {
                    ForEach([15, 30, 45, 60, 120], id: \.self) { mins in
                        let label = mins >= 60 ? "\(mins / 60) giờ" : "\(mins) phút"
                        let isSelected = power.isSleepTimerActive && Int(round(power.sleepTimerRemainingSeconds / 60)) == mins
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                power.startSleepTimer(minutes: mins, action: power.sleepTimerAction)
                            }
                        }) {
                            Text(label)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? Color(hex: "A855F7").opacity(0.85) : Color.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(isSelected ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Action Selection Row
            VStack(alignment: .leading, spacing: 6) {
                Text("HÀNH ĐỘNG KHI HẾT GIỜ")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                
                HStack(spacing: 8) {
                    actionButton(act: .sleepNow)
                    actionButton(act: .shutDown)
                    actionButton(act: .lockScreen)
                    actionButton(act: .displaySleep)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(power.isSleepTimerActive ? Color(hex: "A855F7").opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private func actionButton(act: SystemPowerAction) -> some View {
        let isSelected = power.sleepTimerAction == act
        return Button(action: {
            power.sleepTimerAction = act
        }) {
            HStack(spacing: 5) {
                Image(systemName: act.icon)
                    .font(.system(size: 10))
                Text(act.title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(hex: "A855F7").opacity(0.25) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? Color(hex: "A855F7").opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Smart Network Trigger Card (Auto Sleep/Shutdown on Download Complete)

struct SmartNetworkTriggerCard: View {
    @ObservedObject private var net = NetworkSpeedMonitor.shared
    @ObservedObject private var power = PowerManager.shared
    
    private var isNetworkActive: Bool {
        if case .networkIdle = power.currentSession {
            return true
        }
        return false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            
            if net.countdownWarningSeconds != nil {
                warningCountdownBanner
            } else if isNetworkActive {
                liveSafetyProgressView
            }
            
            masterActionButton
            
            Divider().background(Color.white.opacity(0.05))
            
            configurationGrid
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            isNetworkActive ? Color(hex: "38BDF8").opacity(0.3) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
    }
    
    private var headerRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "38BDF8"))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Tự động tắt máy / ngủ khi tải xong")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Giám sát tốc độ mạng, tự thực hiện hành động khi hoàn tất truyền tải")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            // Live Speed Pill Badges
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(net.formattedDownloadSpeed)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(hex: "38BDF8"))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: "38BDF8").opacity(0.12)))
                
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                    Text(net.formattedUploadSpeed)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
    }
    
    private var warningCountdownBanner: some View {
        let warnSec = net.countdownWarningSeconds ?? 0
        return HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "F59E0B"))
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Đã xong tải! Sẽ \(net.selectedAction.title) sau \(warnSec) giây")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.white)
                Text("Bấm Huỷ bỏ nếu bạn vẫn đang làm việc trên máy")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Button("Huỷ bỏ ngay") {
                net.cancelWarning()
            }
            .font(.system(size: 10.5, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.red.opacity(0.8)))
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.red.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.red.opacity(0.3), lineWidth: 1))
    }
    
    private var liveSafetyProgressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if net.consecutiveIdleSeconds > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: "F59E0B")).frame(width: 6, height: 6)
                        Text("Đang đếm thời gian an toàn: \(net.consecutiveIdleSeconds)s / \(net.safetyDurationSeconds)s (Tốc độ < \(Int(net.thresholdKBps)) KB/s)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "F59E0B"))
                    }
                } else {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: "10B981")).frame(width: 6, height: 6)
                        Text("Đang truyền tải dữ liệu (> \(Int(net.thresholdKBps)) KB/s) • Giữ thức liên tục")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "10B981"))
                    }
                }
                
                Spacer()
                
                Text(net.consecutiveIdleSeconds > 0 ? "\(Int(net.safetyProgress * 100))%" : "HOẠT ĐỘNG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 4)
                    
                    Capsule()
                        .fill(Color(hex: "38BDF8"))
                        .frame(width: max(4, proxy.size.width * CGFloat(net.safetyProgress)), height: 4)
                        .animation(.linear(duration: 0.3), value: net.safetyProgress)
                }
            }
            .frame(height: 4)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.02)))
    }
    
    private var masterActionButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                if isNetworkActive {
                    power.endSession(reason: "Người dùng dừng giám sát tải")
                } else {
                    power.startNetworkIdleSession()
                }
            }
        }) {
            HStack(spacing: 7) {
                Image(systemName: isNetworkActive ? "stop.fill" : "play.fill")
                    .font(.system(size: 10))
                Text(isNetworkActive ? "Dừng giám sát tải" : "Kích hoạt: Tự động \(net.selectedAction.title.lowercased()) khi tải xong")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isNetworkActive ? Color(hex: "EF4444") : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isNetworkActive ? Color.red.opacity(0.12) : Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isNetworkActive ? Color.red.opacity(0.3) : Color.white.opacity(0.16), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var configurationGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            actionRow
            safetyRow
            thresholdRow
            togglesRow
        }
    }
    
    // Unified Elegant Segmented Styling
    private func segmentedButton(label: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.vertical, 5.5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? CFinderTheme.primary.opacity(0.18) : Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? CFinderTheme.primaryLight.opacity(0.35) : Color.white.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("HÀNH ĐỘNG KHI HOÀN TẤT")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            HStack(spacing: 6) {
                ForEach(SystemPowerAction.allCases) { act in
                    segmentedButton(
                        label: act.title,
                        icon: act.icon,
                        isSelected: net.selectedAction == act
                    ) {
                        net.selectedAction = act
                    }
                }
            }
        }
    }
    
    private var safetyRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("THỜI GIAN AN TOÀN (GRACE PERIOD)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Text("Mạng duy trì < ngưỡng trong thời gian này")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            HStack(spacing: 6) {
                ForEach([15, 30, 60, 120, 300], id: \.self) { sec in
                    let label = sec >= 60 ? "\(sec / 60) phút" : "\(sec)s"
                    segmentedButton(
                        label: label,
                        isSelected: net.safetyDurationSeconds == sec
                    ) {
                        net.safetyDurationSeconds = sec
                    }
                }
            }
        }
    }
    
    private var thresholdRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("NGƯỠNG TỐC ĐỘ HOÀN TẤT")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Text("Dưới ngưỡng này tính là bắt đầu xong tải")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            HStack(spacing: 6) {
                ForEach([25.0, 50.0, 100.0, 250.0, 500.0, 1024.0], id: \.self) { kb in
                    let label = kb >= 1024 ? "1 MB/s" : "\(Int(kb)) KB/s"
                    segmentedButton(
                        label: label,
                        isSelected: net.thresholdKBps == kb
                    ) {
                        net.thresholdKBps = kb
                    }
                }
            }
        }
    }
    
    private var togglesRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HƯỚNG GIÁM SÁT")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                
                Picker("", selection: $net.monitorDirection) {
                    ForEach(NetworkMonitorDirection.allCases) { dir in
                        Text(dir.title).tag(dir)
                    }
                }
                .labelsHidden()
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("CẢNH BÁO TRƯỚC")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                
                Toggle("Đếm ngược 10s trước khi thực hiện", isOn: $net.warnBeforeAction)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.75))
                    .cfinderToggleStyle()
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Rename Tab Content

struct RenameTabContentView: View {
    @Binding var autoCleanRenameList: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "pencil.and.list.clipboard")
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Batch Rename Studio trên Finder")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Đổi tên tệp cực nhanh theo Số thứ tự, Thêm chữ trước/sau, Format hoa thường và Hoàn tác (⌘Z) an toàn 100%.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.68))
                }
                
                Spacer()
                
                Button("Mở Studio Đổi tên") {
                    HostActionCoordinator.shared.presentBatchRename(urls: [])
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.orange))
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
            
            // Rename Behavior Options
            VStack(alignment: .leading, spacing: 10) {
                Text("CÀI ĐẶT HÀNH VI ĐỔI TÊN")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.45))
                
                VStack(spacing: 0) {
                    LiquidGlassToggleRow(
                        title: "Tự động làm sạch danh sách sau khi đổi tên xong",
                        subtitle: "Lần mở Studio tiếp theo sẽ bắt đầu với danh sách tệp hoàn toàn trống",
                        icon: "sparkles",
                        isOn: $autoCleanRenameList
                    ) { _ in }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
            }
            
            // Finder Context Menu Guide
            VStack(alignment: .leading, spacing: 10) {
                Text("HƯỚNG DẪN SỬ DỤNG TRÊN FINDER")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.45))
                
                VStack(alignment: .leading, spacing: 12) {
                    GuideStepRow(step: "1", title: "Quét chọn các tệp cần đổi tên trong Finder", desc: "Chọn nhiều tệp ảnh, video, tài liệu hoặc một thư mục bất kỳ.")
                    GuideStepRow(step: "2", title: "Nhấp chuột phải vào các tệp", desc: "Menu ngữ cảnh của Finder sẽ hiển thị mục 'CFinder — Đổi tên hàng loạt...'.")
                    GuideStepRow(step: "3", title: "Tùy biến cấu hình và Đổi tên an toàn", desc: "Xem trước kết quả trực tiếp thời gian thực, có hỗ trợ Hoàn tác (⌘Z) an toàn 100%.")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
                )
            }
        }
    }
}

// MARK: - General Tab Content

struct GeneralTabContentView: View {
    @Binding var launchAtLoginEnabled: Bool
    @Binding var playGeneralSounds: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("CÀI ĐẶT HỆ THỐNG CHUNG")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white.opacity(0.45))
                
                VStack(spacing: 0) {
                    LiquidGlassToggleRow(
                        title: "Tự khởi động cùng macOS (Launch at Login)",
                        subtitle: "Tự động chạy CFinder ở Menu Bar mỗi khi bạn đăng nhập máy Mac",
                        icon: "power",
                        isOn: $launchAtLoginEnabled
                    ) { val in
                        PermissionsManager.shared.toggleLaunchAtLogin(enabled: val)
                        onRefresh()
                    }
                    
                    Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                    
                    LiquidGlassToggleRow(
                        title: "Âm thanh hiệu ứng thông báo",
                        subtitle: "Phát âm thanh nhẹ nhàng khi hoàn thành đổi tên hoặc nhận diện OCR",
                        icon: "speaker.wave.2.fill",
                        isOn: $playGeneralSounds
                    ) { _ in }
                    
                    Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 16)
                    
                    LiquidGlassToggleRow(
                        title: "Cắt & Dán tệp Finder như Windows (⌘X & ⌘V)",
                        subtitle: "Nhấn ⌘X để cắt tệp đã chọn, mở thư mục mới và nhấn ⌘V để dán/di chuyển",
                        icon: "scissors",
                        isOn: Binding(
                            get: { FinderCutManager.shared.isEnabled },
                            set: { val in
                                FinderCutManager.shared.isEnabled = val
                                UserDefaults.standard.set(val, forKey: "sfinder_enable_finder_cut")
                            }
                        )
                    ) { _ in }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
            }
            
            // App Info Box
            HStack(spacing: 14) {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.5))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("CFinder Pro v1.0.0 — Native macOS Engine")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Thiết kế theo chuẩn Apple Liquid Glass, tối ưu hóa phần cứng Apple Silicon M1/M2/M3/M4.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
        }
    }
}

// MARK: - Shared Liquid Glass Components

struct LiquidGlassToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var accentColor: Color = CFinderTheme.primary
    @Binding var isOn: Bool
    let onChange: (Bool) -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(isOn ? CFinderTheme.primary : .white.opacity(0.45))
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .cfinderToggleStyle()
                .labelsHidden()
                .onChange(of: isOn) { _, newVal in
                    onChange(newVal)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct SidebarItemButton: View {
    let tab: DashboardTab
    @Binding var selectedTab: DashboardTab
    let badge: String?
    var badgeColor: Color? = nil
    @State private var isHovered: Bool = false
    
    private var isSelected: Bool {
        selectedTab == tab
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        }) {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? tab.accentColor : (isHovered ? .white.opacity(0.9) : .white.opacity(0.5)))
                    .frame(width: 18)
                
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : (isHovered ? .white : .white.opacity(0.7)))
                    .lineLimit(1)
                
                Spacer()
                
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(badgeColor ?? (isSelected ? tab.accentColor.opacity(0.95) : .white.opacity(0.45)))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(isSelected ? tab.accentColor.opacity(0.2) : Color.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tab.accentColor.opacity(0.14) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? tab.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .padding(.horizontal, 10)
        .onHover { h in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = h
            }
        }
    }
}

struct SidebarShortcutPill: View {
    let key: String
    let label: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
        }
    }
}

struct LiquidToolCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    let statusBadge: String
    let actionLabel: String
    let onAction: () -> Void
    let onConfigure: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(isHovered ? accentColor.opacity(0.18) : Color.white.opacity(0.06))
                        .frame(width: 34, height: 34)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(accentColor)
                }
                
                Spacer()
                
                Text(statusBadge)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isHovered ? accentColor : .white.opacity(0.55))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(isHovered ? accentColor.opacity(0.14) : Color.white.opacity(0.06)))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
            }
            
            Spacer(minLength: 4)
            
            HStack(spacing: 8) {
                Button(actionLabel, action: onAction)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5.5)
                    .background(
                        Capsule()
                            .fill(isHovered ? accentColor.opacity(0.2) : Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(isHovered ? accentColor.opacity(0.4) : Color.white.opacity(0.14), lineWidth: 1)
                            )
                    )
                    .buttonStyle(.plain)
                    .focusable(false)
                
                Spacer()
                
                Button(action: onConfigure) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5))
                        .foregroundColor(isHovered ? accentColor.opacity(0.8) : .white.opacity(0.4))
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Cài đặt chi tiết")
            }
        }
        .padding(16)
        .frame(minHeight: 155)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? accentColor.opacity(0.07) : Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isHovered ? accentColor.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 8, y: 3)
        )
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .onHover { h in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                isHovered = h
            }
        }
    }
}

struct PermissionRowView: View {
    let type: PermissionType
    let isGranted: Bool
    let onRequest: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundColor(isGranted ? Color(hex: "10B981") : Color(hex: "F59E0B"))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(type.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                Text(type.purpose)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            
            Spacer()
            
            if isGranted {
                Text("Đã cấp ✓")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Color(hex: "10B981"))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color(hex: "10B981").opacity(0.10)))
            } else {
                Button("Cấp quyền", action: onRequest)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Color(hex: "F59E0B").opacity(0.4), lineWidth: 1)
                            )
                    )
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.05), lineWidth: 1))
        )
    }
}

struct DetailedPermissionCard: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let buttonTitle: String
    let action: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isGranted ? Color(hex: "10B981").opacity(0.12) : Color(hex: "F59E0B").opacity(0.12))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(isGranted ? Color(hex: "10B981") : Color(hex: "F59E0B"))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(isGranted ? "Đã sẵn sàng" : "Chưa kích hoạt")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(isGranted ? Color(hex: "10B981") : Color(hex: "F59E0B"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill((isGranted ? Color(hex: "10B981") : Color(hex: "F59E0B")).opacity(0.10)))
                }
                
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isGranted ? 0.08 : 0.14))
                            .overlay(
                                Capsule()
                                    .stroke(isGranted ? Color.white.opacity(0.12) : Color(hex: "F59E0B").opacity(0.35), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}

struct GuideStepRow: View {
    let step: String
    let title: String
    let desc: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FF6A00").opacity(0.2))
                    .frame(width: 22, height: 22)
                Text(step)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "FF6A00"))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

struct ShortcutRecordButton: View {
    let isRecording: Bool
    let currentPresetDisplay: String
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                if isRecording {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("Gõ phím bất kỳ...")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Text(currentPresetDisplay)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("(Đổi phím)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isRecording ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isRecording ? Color.red : Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
