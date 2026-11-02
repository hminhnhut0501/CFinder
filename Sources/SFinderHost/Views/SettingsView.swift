import SwiftUI
import AppKit
import ServiceManagement
import Carbon
import SFinderCore

public struct SettingsView: View {
    @State private var selectedTab: Int = 0
    
    // OCR settings state
    @State private var currentPresetID: String = ScreenOCREngine.shared.currentPreset.id
    @State private var currentDisplayShortcut: String = ScreenOCREngine.shared.currentPreset.displayShortcut
    @State private var isRecordingShortcut: Bool = false
    @State private var ignoreLineBreaks: Bool = ScreenOCREngine.shared.ignoreLineBreaks
    @State private var tableDetection: Bool = ScreenOCREngine.shared.tableDetection
    @State private var autoOpenURL: Bool = ScreenOCREngine.shared.autoOpenURL
    @State private var detectQR: Bool = ScreenOCREngine.shared.detectQR
    @State private var playSound: Bool = ScreenOCREngine.shared.playSound
    
    // Power settings state
    @State private var allowDisplaySleep: Bool = PowerManager.shared.allowDisplaySleep
    @State private var stopOnLowBattery: Bool = PowerManager.shared.stopOnLowBattery
    
    // System launch at login
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    
    @State private var keyMonitor: Any?
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CFinderTheme.primary)
                
                Text("CFinder — Cài đặt hệ thống")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Tabs
                HStack(spacing: 4) {
                    TabPill(title: "Quét chữ OCR", icon: "text.viewfinder", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    TabPill(title: "Giữ thức máy", icon: "bolt.fill", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    TabPill(title: "Hệ thống", icon: "macwindow", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.03))
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Tab contents
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    if selectedTab == 0 {
                        ocrSettingsSection
                    } else if selectedTab == 1 {
                        powerSettingsSection
                    } else {
                        systemSettingsSection
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 580, height: 490)
        .background(
            ZStack {
                Color(red: 0.10, green: 0.11, blue: 0.15)
                RadialGradient(
                    colors: [CFinderTheme.primary.opacity(0.12), Color.clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 400
                )
            }
        )
        .onDisappear {
            stopRecordingMonitor()
        }
    }
    
    // MARK: - OCR Settings Tab
    
    private var ocrSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section 1: Phím tắt toàn cục
            VStack(alignment: .leading, spacing: 10) {
                Text("PHÍM TẮT TOÀN CỤC QUÉT MÀN HÌNH")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Phím kích hoạt nhanh:")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Text("Nhấn phím tắt ở bất cứ đâu để mở tâm ngắm khoanh vùng quét.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    // Shortcut recording box
                    Button(action: {
                        if isRecordingShortcut {
                            stopRecordingMonitor()
                        } else {
                            startRecordingMonitor()
                        }
                    }) {
                        HStack(spacing: 6) {
                            if isRecordingShortcut {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 7, height: 7)
                                Text("Bấm phím bất kỳ...")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            } else {
                                Text(currentDisplayShortcut)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(CFinderTheme.primary)
                                Text("(Bấm để đổi)")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isRecordingShortcut ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isRecordingShortcut ? Color.red : Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button("Mặc định (⌥C)") {
                        ScreenOCREngine.shared.resetToDefaultHotKey()
                        currentDisplayShortcut = "⌥C"
                    }
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.7))
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            }
            
            // Section 2: Chế độ quét & Xử lý văn bản
            VStack(alignment: .leading, spacing: 10) {
                Text("CHẾ ĐỘ QUÉT & ĐỊNH DẠNG VĂN BẢN (TRex Style)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                
                VStack(spacing: 0) {
                    SettingToggleRow(
                        title: "Bỏ qua ngắt dòng (Gộp đoạn văn)",
                        subtitle: "Tự động nối các dòng ngắt đoạn thành một đoạn văn liền mạch",
                        icon: "text.alignleft",
                        isOn: $ignoreLineBreaks
                    ) { val in
                        ScreenOCREngine.shared.ignoreLineBreaks = val
                    }
                    
                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 14)
                    
                    SettingToggleRow(
                        title: "Nhận diện bảng biểu (Table Detection)",
                        subtitle: "Sắp xếp hàng cột và phân tách bằng tab (TSV) để dán vào Excel / Numbers",
                        icon: "tablecells",
                        isOn: $tableDetection
                    ) { val in
                        ScreenOCREngine.shared.tableDetection = val
                    }
                    
                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 14)
                    
                    SettingToggleRow(
                        title: "Tự động mở liên kết nếu là URL web",
                        subtitle: "Nếu văn bản nhận diện được là đường link, tự động mở trình duyệt web",
                        icon: "safari",
                        isOn: $autoOpenURL
                    ) { val in
                        ScreenOCREngine.shared.autoOpenURL = val
                    }
                    
                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 14)
                    
                    SettingToggleRow(
                        title: "Nhận diện mã QR Code & Barcode",
                        subtitle: "Tự động giải mã chuỗi từ mã QR hoặc Barcode song song với chữ",
                        icon: "qrcode",
                        isOn: $detectQR
                    ) { val in
                        ScreenOCREngine.shared.detectQR = val
                    }
                    
                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 14)
                    
                    SettingToggleRow(
                        title: "Âm thanh hiệu ứng chụp máy ảnh",
                        subtitle: "Phát tiếng shutter nhẹ nhàng khi chụp và quét chữ thành công",
                        icon: "speaker.wave.2.fill",
                        isOn: $playSound
                    ) { val in
                        ScreenOCREngine.shared.playSound = val
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            }
        }
    }
    
    // MARK: - Power Management Tab
    
    private var powerSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("QUẢN LÝ NGUỒN & GIỮ THỨC MAC (AMPHETAMINE STYLE)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                
                VStack(spacing: 0) {
                    SettingToggleRow(
                        title: "Cho phép tắt màn hình (Display Sleep)",
                        subtitle: "Màn hình vẫn có thể tắt tiết kiệm pin trong khi CPU tiếp tục giữ thức để tải file/render",
                        icon: "display",
                        isOn: $allowDisplaySleep
                    ) { val in
                        PowerManager.shared.allowDisplaySleep = val
                    }
                    
                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 14)
                    
                    SettingToggleRow(
                        title: "Tự ngắt giữ thức khi pin yếu (<10%)",
                        subtitle: "Tự động kết thúc phiên giữ thức để bảo vệ tuổi thọ pin khi máy sắp hết điện",
                        icon: "battery.25",
                        isOn: $stopOnLowBattery
                    ) { val in
                        PowerManager.shared.stopOnLowBattery = val
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            }
            
            // Info card
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 16))
                
                Text("Mẹo: Nhấn phím ⌘I để bật/tắt nhanh giữ thức máy từ bất kỳ đâu. Hoặc chọn ứng dụng đang chạy từ menu bar để máy luôn thức khi app đó đang hoạt động.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.cyan.opacity(0.1)))
        }
    }
    
    // MARK: - System Tab
    
    private var systemSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("TỰ ĐỘNG KHỞI ĐỘNG CÙNG MAC")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                
                VStack(spacing: 0) {
                    SettingToggleRow(
                        title: "Chạy SFinder khi đăng nhập macOS",
                        subtitle: "Tự động kích hoạt thanh Menu bar và phím tắt quét màn hình khi mở máy",
                        icon: "power",
                        isOn: $launchAtLogin
                    ) { val in
                        do {
                            if val {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            NSLog("[SFinder] Error setting launch at login: %@", error.localizedDescription)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            }
            
            // App About & Version Info
            VStack(spacing: 12) {
                Image(systemName: "apple.terminal.on.rectangle")
                    .font(.system(size: 32))
                    .foregroundColor(CFinderTheme.primary)
                
                Text("CFinder Studio v2.0")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Bộ công cụ Nâng cao tích hợp hoàn hảo cho macOS Finder:\n• Quét chữ tiếng Việt OCR chuẩn xác từng dấu câu (Phong cách TRex)\n• Quản lý nguồn & Chống ngủ thông minh (Phong cách Amphetamine)\n• Đổi tên tệp hàng loạt trực tiếp từ chuột phải Finder")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
        }
    }
    
    // MARK: - Shortcut Recorder Helpers
    
    private func startRecordingMonitor() {
        isRecordingShortcut = true
        stopRecordingMonitor()
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
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
            
            // Save and apply new hotkey
            ScreenOCREngine.shared.setCustomHotKey(
                keyCode: UInt32(event.keyCode),
                modifiers: carbonMods,
                display: fullDisplay
            )
            self.currentDisplayShortcut = fullDisplay
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

// MARK: - Reusable Components

struct TabPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.65))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct SettingToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    let onChange: (Bool) -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(CFinderTheme.primary)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .cfinderToggleStyle()
                .labelsHidden()
                .onChange(of: isOn) { newVal in
                    onChange(newVal)
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
