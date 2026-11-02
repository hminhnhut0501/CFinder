import SwiftUI
import AppKit

// MARK: - Color Hex Initializer
public extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - CFinder Design System & Color Palette
/// Bộ quy chuẩn màu sắc và phong cách giao diện Liquid Glass chuẩn Apple bám sát Logo CFinder (Smiling Azure Face).
public enum CFinderTheme {
    
    // MARK: 1. Core Brand Colors (Logo Smiling C Face)
    /// Màu xanh Azure biểu tượng chính (Sky Blue #0EA5E9) - Điểm nhấn nhận diện thương hiệu
    public static let primary = Color(hex: "0EA5E9")
    /// Màu xanh Cyan sáng (Electric Cyan #38BDF8) - Dùng cho viền phát sáng, text nổi bật, gradient highlight
    public static let primaryLight = Color(hex: "38BDF8")
    /// Màu xanh Deep Ocean (#0284C7) - Dùng cho nút bấm, nền phụ, gradient anchor
    public static let primaryDark = Color(hex: "0284C7")
    /// Màu Ice Frost (#E0F2FE) - Dùng cho icon trắng ngả lam, viền tinh tế
    public static let frost = Color(hex: "E0F2FE")
    
    // MARK: 2. Semantic Functional Colors
    /// Màu bật switch toàn hệ thống (Active Toggle Tint) - Đảm bảo mọi nút bật tắt trong app ĐỒNG NHẤT 100%
    public static let toggleTint = Color(hex: "0EA5E9")
    
    /// Màu trạng thái hoạt động hoàn hảo (3/3 Quyền, Hệ thống sẵn sàng)
    public static let success = Color(hex: "10B981")
    /// Màu trạng thái cảnh báo / Chống ngủ đang đếm giờ (Sleep session active, Attention)
    public static let warning = Color(hex: "F59E0B")
    /// Màu thao tác huỷ / Nguy hiểm / Thoát app (Destructive / Danger)
    public static let danger = Color(hex: "EF4444")
    
    // MARK: 3. Neutral Dark Obsidian Glass Surfaces
    /// Nền đen sâu Obsidian (Cửa sổ chính)
    public static let backgroundBase = Color(hex: "111215")
    /// Nền Sidebar mờ
    public static let backgroundSidebar = Color(hex: "15171C")
    /// Nền Card / Thẻ công cụ
    public static let cardSurface = Color.white.opacity(0.035)
    /// Nền Card khi Hover
    public static let cardSurfaceHover = Color.white.opacity(0.065)
    /// Viền mờ thuỷ tinh
    public static let cardBorder = Color.white.opacity(0.075)
    /// Viền kích hoạt / Đang chọn (Brand highlight)
    public static let cardBorderActive = Color(hex: "38BDF8").opacity(0.35)
    
    // MARK: 4. Text Hierarchy
    public static let textPrimary = Color.white.opacity(0.95)
    public static let textSecondary = Color.white.opacity(0.65)
    public static let textMuted = Color.white.opacity(0.38)
    public static let textAccent = Color(hex: "38BDF8")
    
    // MARK: 5. Gradients
    /// Gradient thương hiệu CFinder (Ocean -> Cyan)
    public static let brandGradient = LinearGradient(
        colors: [Color(hex: "0284C7"), Color(hex: "38BDF8")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Gradient viền sáng tinh tế
    public static let borderGradient = LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04), Color.clear],
        startPoint: .top,
        endPoint: .bottom
    )
    
    /// Gradient phát sáng nền khi được chọn (Active Glow)
    public static let activeGlowGradient = LinearGradient(
        colors: [Color(hex: "0EA5E9").opacity(0.18), Color(hex: "38BDF8").opacity(0.04)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Standard View Modifiers & Components

/// Switch Toggle Style tiêu chuẩn của CFinder
public struct CFinderSwitchToggleStyle: ToggleStyle {
    public init() {}
    
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Toggle("", isOn: configuration.$isOn)
                .toggleStyle(SwitchToggleStyle(tint: CFinderTheme.toggleTint))
                .labelsHidden()
        }
    }
}

public extension View {
    /// Áp dụng màu Switch chuẩn CFinder Brand (Azure Blue) cho mọi Toggle
    func cfinderToggleStyle() -> some View {
        self.toggleStyle(SwitchToggleStyle(tint: CFinderTheme.toggleTint))
    }
    
    /// Bọc view trong khung Obsidian Glass chuẩn
    func cfinderCardStyle(
        cornerRadius: CGFloat = 14,
        isActive: Bool = false,
        padding: CGFloat = 16
    ) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isActive ? CFinderTheme.primary.opacity(0.06) : CFinderTheme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                isActive ? CFinderTheme.cardBorderActive : CFinderTheme.cardBorder,
                                lineWidth: 1
                            )
                    )
            )
    }
}
