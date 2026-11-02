import SwiftUI
import AppKit
import SFinderCore

public struct SnapTabContentView: View {
    @ObservedObject private var snap = WindowSnapManager.shared
    @State private var selectedScreen: NSScreen? = NSScreen.main ?? NSScreen.screens.first
    
    public init() {}
    
    private var currentConfig: ScreenSnapConfig {
        guard let s = selectedScreen else {
            return ScreenSnapConfig(screenKey: "default", displayName: "Màn hình chính")
        }
        return snap.config(for: s)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            heroMasterCard
            screenSelectorSection
            interactiveVisualMap
            screenCustomizationCard
            keyboardShortcutsSection
        }
    }
    
    // MARK: - Master Hero Card
    
    private var heroMasterCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                
                Image(systemName: "rectangle.split.2x2")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Tính năng Snap Areas & Bố cục cửa sổ")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Kéo cửa sổ chạm mép màn hình để chia đôi, chạm góc để chia tư. Hỗ trợ đa màn hình độc lập.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: $snap.isSnapEnabled)
                .cfinderToggleStyle()
                .labelsHidden()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Screen Selector Bar (Vùng tuỳ chỉnh cho từng màn hình)
    
    private var screenSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TUỲ CHỈNH CHO TỪNG MÀN HÌNH")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            HStack(spacing: 10) {
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                    let isSelected = selectedScreen == screen
                    let cfg = snap.config(for: screen)
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedScreen = screen
                        }
                    }) {
                        HStack(spacing: 7) {
                            Image(systemName: index == 0 ? "display" : "display.2")
                                .font(.system(size: 12))
                            Text(cfg.displayName)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
        }
    }
    
    // MARK: - Interactive Visual Layout Map
    
    private var interactiveVisualMap: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SƠ ĐỒ VÙNG SNAP TƯƠNG TÁC (NHẤP ĐỂ THỬ)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Text("Bấm vào vùng bất kỳ để chia cửa sổ đang mở")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            ZStack {
                // Monitor Bezel Frame
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .frame(height: 180)
                
                // 1. Top Edge Strip: Maximize
                VStack {
                    Button(action: { snap.snapFrontmost(to: .maximize) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10))
                            Text("Kéo mép trên: Toàn màn hình (Maximize)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    
                    Spacer()
                    
                    // 2. Middle Row: Corners & Halves
                    HStack(spacing: 8) {
                        // Left Half Box
                        Button(action: { snap.snapFrontmost(to: .leftHalf) }) {
                            VStack(spacing: 4) {
                                Image(systemName: "rectangle.lefthalf.filled")
                                    .font(.system(size: 14))
                                Text("Trái 50%")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        
                        // Center Info / Actions
                        VStack(spacing: 6) {
                            Button(action: { snap.snapFrontmost(to: .center) }) {
                                Text("Căn giữa")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4.5)
                                    .background(Capsule().fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                        }
                        .frame(width: 80)
                        
                        // Right Half Box
                        Button(action: { snap.snapFrontmost(to: .rightHalf) }) {
                            VStack(spacing: 4) {
                                Image(systemName: "rectangle.righthalf.filled")
                                    .font(.system(size: 14))
                                Text("Phải 50%")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                    .padding(.horizontal, 8)
                    
                    Spacer()
                    
                    // 3. Bottom Edge Strip: Bottom Half
                    Button(action: { snap.snapFrontmost(to: .bottomHalf) }) {
                        Text("Kéo mép dưới: Nửa dưới màn hình (50%)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                            )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }
    
    // MARK: - Per-Screen Customization Controls
    
    private var screenCustomizationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CẤU HÌNH VÙNG SNAP CHO \(currentConfig.displayName.uppercased())")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
            }
            
            // Window Gap Selector
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Khoảng cách viền cửa sổ (Window Gap):")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text("\(Int(currentConfig.windowGap)) px")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                HStack(spacing: 8) {
                    ForEach([0, 4, 6, 8, 12, 16], id: \.self) { g in
                        let isSelected = Int(currentConfig.windowGap) == g
                        Button(action: {
                            var updated = currentConfig
                            updated.windowGap = CGFloat(g)
                            snap.updateConfig(updated)
                        }) {
                            Text(g == 0 ? "0px (Liền)" : "\(g)px")
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(isSelected ? Color.white.opacity(0.25) : Color.clear, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
            
            // Toggle Rows
            VStack(spacing: 0) {
                toggleRow(
                    title: "Bật kéo mép trên để phóng to (Top Edge Maximize)",
                    subtitle: "Phóng to cửa sổ lấp đầy màn hình khi kéo chạm mép trên cùng",
                    isOn: Binding(
                        get: { currentConfig.enableTopMaximize },
                        set: { val in
                            var u = currentConfig
                            u.enableTopMaximize = val
                            snap.updateConfig(u)
                        }
                    )
                )
                
                Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 14)
                
                toggleRow(
                    title: "Bật chia đôi khi kéo ra hai mép bên (Left & Right Halves)",
                    subtitle: "Tự động xếp 50% bên trái hoặc bên phải màn hình",
                    isOn: Binding(
                        get: { currentConfig.enableSideHalves },
                        set: { val in
                            var u = currentConfig
                            u.enableSideHalves = val
                            snap.updateConfig(u)
                        }
                    )
                )
                
                Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 14)
                
                toggleRow(
                    title: "Bật chia tư khi kéo vào 4 góc (Corner Quarters)",
                    subtitle: "Kéo vào góc trên/dưới để chia 25% diện tích màn hình",
                    isOn: Binding(
                        get: { currentConfig.enableCorners },
                        set: { val in
                            var u = currentConfig
                            u.enableCorners = val
                            snap.updateConfig(u)
                        }
                    )
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.025))
            )
        }
    }
    
    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .cfinderToggleStyle()
                .labelsHidden()
        }
        .padding(14)
    }
    
    // MARK: - Keyboard Shortcuts Section
    
    private var keyboardShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHÍM TẮT TIỆN ÍCH (SNAP TOÀN HỆ THỐNG)")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                shortcutBadge(key: "⌃⌥ ↑", action: "Toàn màn hình")
                shortcutBadge(key: "⌃⌥ ←", action: "Chia đôi trái 50%")
                shortcutBadge(key: "⌃⌥ →", action: "Chia đôi phải 50%")
                shortcutBadge(key: "⌃⌥ U", action: "Góc trên trái 25%")
                shortcutBadge(key: "⌃⌥ I", action: "Góc trên phải 25%")
                shortcutBadge(key: "⌃⌥ C", action: "Căn giữa màn hình")
                shortcutBadge(key: "⌃⌥ J", action: "Góc dưới trái 25%")
                shortcutBadge(key: "⌃⌥ K", action: "Góc dưới phải 25%")
                shortcutBadge(key: "⌃⌥ ↓", action: "Chia nửa dưới 50%")
            }
        }
    }
    
    private func shortcutBadge(key: String, action: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
            
            Text(action)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.65))
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }
}
