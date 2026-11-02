import SwiftUI
import AppKit
import SFinderCore

public struct MenuBarIconsTabContentView: View {
    @ObservedObject private var manager = MenuBarIconManager.shared
    @State private var isHoveringOrganizeButton = false
    @State private var isHoveringTestButton = false
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            heroMasterCard
            interactiveOrganizeModeCard
            liveStatusAndPreviewCard
            autoHideConfigurationCard
            interactionOptionsCard
            illustratedGuideCard
        }
    }
    
    // MARK: - Master Hero Card
    
    private var heroMasterCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "38BDF8").opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(hex: "38BDF8").opacity(0.25), lineWidth: 1)
                    )
                
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(hex: "38BDF8"))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Quản lý biểu tượng Menu Bar")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Giấu bớt các icon tiện ích để thanh menu gọn gàng, tự động ẩn lại sau khi dùng.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: $manager.isEnabled)
                .cfinderToggleStyle()
                .labelsHidden()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Organize Mode Card (⌘-Drag Mode)
    
    private var interactiveOrganizeModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(manager.isOrganizingMode ? Color(hex: "38BDF8").opacity(0.25) : Color.white.opacity(0.06))
                        .frame(width: 28, height: 28)
                    Image(systemName: manager.isOrganizingMode ? "hand.draw.fill" : "command")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(manager.isOrganizingMode ? Color(hex: "38BDF8") : .white.opacity(0.8))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isOrganizingMode ? "ĐANG BẬT CHẾ ĐỘ SẮP XẾP ICON" : "Chế độ kéo sắp xếp Icon (⌘ + Drag)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(manager.isOrganizingMode ? Color(hex: "38BDF8") : .white)
                    
                    Text(manager.isOrganizingMode ? "Thanh menu đang mở & tạm dừng tự ẩn. Bạn hãy giữ phím ⌘ và kéo icon ngay trên thanh menu!" : "Kích hoạt để mở rộng thanh menu bar và tạm dừng tự ẩn giúp bạn kéo icon dễ dàng.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.65))
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        manager.isOrganizingMode.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: manager.isOrganizingMode ? "checkmark.circle.fill" : "arrow.up.left.and.arrow.down.right")
                        Text(manager.isOrganizingMode ? "Hoàn tất sắp xếp" : "Bắt đầu sắp xếp")
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(manager.isOrganizingMode ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(manager.isOrganizingMode ? Color(hex: "38BDF8") : Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(manager.isOrganizingMode ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            
            if manager.isOrganizingMode {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "F59E0B"))
                    Text("Mẹo: Nhấn giữ phím **⌘ (Command)** trên bàn phím Mac, sau đó bấm giữ chuột vào bất kỳ icon nào trên thanh menu để kéo qua trái vạch **|** (để ẩn) hoặc qua phải nút **◀** (để luôn hiện).")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: "F59E0B").opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: "F59E0B").opacity(0.25), lineWidth: 1)
                        )
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(manager.isOrganizingMode ? Color(hex: "38BDF8").opacity(0.06) : Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(manager.isOrganizingMode ? Color(hex: "38BDF8").opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Live Status & Preview Card
    
    private var testCardHeader: some View {
        HStack {
            Text("MÔ PHỎNG VỊ TRÍ & TRẠNG THÁI THANH MENU")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            Spacer()
            
            let collapsed = manager.isCollapsed
            Text(collapsed ? "ĐANG THU GỌN (ẨN)" : "ĐANG MỞ RỘNG (HIỆN)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(collapsed ? Color(hex: "94A3B8") : Color(hex: "38BDF8"))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(collapsed ? Color.white.opacity(0.08) : Color(hex: "38BDF8").opacity(0.15))
                )
        }
    }
    
    private var mockMenuBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Apple & Active App
                HStack(spacing: 7) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Finder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Hidden Zone Preview
                HStack(spacing: 6) {
                    if !manager.isCollapsed {
                        HStack(spacing: 7) {
                            Image(systemName: "cloud.fill")
                            Image(systemName: "music.note")
                            Image(systemName: "paperplane.fill")
                        }
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "38BDF8").opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: "38BDF8").opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(hex: "38BDF8").opacity(0.25), lineWidth: 1)
                                )
                        )
                        
                        // Separator Divider |
                        Rectangle()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 1.5, height: 13)
                            .padding(.horizontal, 2)
                    }
                    
                    // Collapse Chevron Button
                    Image(systemName: manager.isCollapsed ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.14)))
                    
                    // Always Visible Zone Preview
                    HStack(spacing: 7) {
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100")
                        Text("23:45")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    }
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )
            
            // Visual Explanatory Sub-labels
            HStack {
                Spacer()
                Text("← Vùng Ẩn (Bên trái |)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color(hex: "38BDF8").opacity(0.7))
                
                Text("•")
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.horizontal, 4)
                
                Text("Vùng Luôn Hiện (Bên phải ◀) →")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 6)
        }
    }
    
    private var testActionButton: some View {
        Button(action: {
            manager.toggle()
        }) {
            HStack(spacing: 7) {
                Image(systemName: manager.isCollapsed ? "chevron.right.2" : "chevron.left.2")
                Text(manager.isCollapsed ? "Mở rộng hiện tất cả biểu tượng (Test)" : "Thu gọn giấu biểu tượng ngay (Test)")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHoveringTestButton ? 0.12 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHoveringTestButton = $0 }
    }
    
    private var liveStatusAndPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            testCardHeader
            mockMenuBar
            testActionButton
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.05), lineWidth: 1))
        )
    }
    
    // MARK: - Auto-Hide Configuration Card
    
    private var delayPillsRow: some View {
        HStack(spacing: 8) {
            ForEach([5.0, 10.0, 15.0, 30.0], id: \.self) { sec in
                let isSelected = manager.autoHideDelay == sec
                Button(action: {
                    manager.autoHideDelay = sec
                }) {
                    Text("\(Int(sec)) giây\(sec == 5.0 ? " (Chuẩn)" : "")")
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color(hex: "38BDF8").opacity(0.2) : Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isSelected ? Color(hex: "38BDF8").opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
    
    private var autoHideConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TỰ ĐỘNG ẨN LẠI (AUTO-REHIDE)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tự động giấu lại khi không tương tác")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white)
                    Text("Sau khi mở để dùng icon, CFinder sẽ tự thu gọn lại để giữ màn hình tối giản.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Toggle("", isOn: $manager.autoHideEnabled)
                    .cfinderToggleStyle()
                    .labelsHidden()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.025)))
            
            if manager.autoHideEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Thời gian chờ trước khi tự ẩn:")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    delayPillsRow
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.025)))
            }
        }
    }
    
    // MARK: - Interaction Options Card
    
    private var interactionOptionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TUỲ CHỌN TƯƠNG TÁC")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            VStack(spacing: 0) {
                toggleRow(
                    title: "Mở rộng khi rê chuột qua (Expand on Hover)",
                    subtitle: "Tự động hiện các icon khi bạn di chuyển con trỏ chuột vào nút mũi tên ◀",
                    isOn: $manager.expandOnHover
                )
                
                Divider().background(Color.white.opacity(0.05)).padding(.horizontal, 14)
                
                toggleRow(
                    title: "Hiển thị vạch ngăn cách | (Separator)",
                    subtitle: "Hiển thị vạch ngăn cách trực quan để phân định ranh giới giữa icon ẩn và hiện",
                    isOn: $manager.showSeparator
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
    
    // MARK: - Illustrated Guide Card
    
    private var illustratedGuideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HƯỚNG DẪN KÉO THẢ SẮP XẾP ICON CHI TIẾT")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            VStack(alignment: .leading, spacing: 10) {
                guideStep(number: "1", text: "Bấm nút \"Bắt đầu sắp xếp\" ở trên (hoặc bấm phím tắt ⌃⌥B) để thanh menu mở rộng và vạch phân cách | xuất hiện.")
                guideStep(number: "2", text: "Nhấn và GIỮ PHÍM ⌘ (Command) trên bàn phím Mac (bắt buộc phải giữ ⌘ để macOS cho phép di chuyển icon).")
                guideStep(number: "3", text: "Dùng chuột bấm và kéo các biểu tượng ứng dụng muốn ẨN sang bên TRÁI vạch |.")
                guideStep(number: "4", text: "Kéo các biểu tượng muốn LUÔN HIỆN sang bên PHẢI nút mũi tên ◀.")
                guideStep(number: "5", text: "Thả phím ⌘. Bấm nút mũi tên ◀ hoặc ⌃⌥B để thu gọn. Hệ thống sẽ tự động lưu vị trí!")
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.05), lineWidth: 1))
            )
        }
    }
    
    private func guideStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "38BDF8"))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color(hex: "38BDF8").opacity(0.12)))
            
            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
    }
}
