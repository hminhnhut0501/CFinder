import SwiftUI
import AppKit
import SFinderCore

public struct NotesTabContentView: View {
    @ObservedObject private var hotspot = EdgeHotspotController.shared
    @ObservedObject private var syncEngine = AppleNotesSyncEngine.shared
    @ObservedObject private var storage = QuickNotesStorage.shared
    @ObservedObject private var drawer = EdgeNotesWindowController.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - Banner Hero
                heroBanner
                
                // MARK: - Section 1: Edge Hotspot & Triggers
                edgeTriggerSection
                
                // MARK: - Section 2: Apple Notes Cloud Sync
                appleNotesSyncSection
                
                // MARK: - Section 3: Notes & Checklist Management
                notesOverviewSection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
    }
    
    // MARK: - 1. Hero Banner
    
    private var heroBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "F59E0B").opacity(0.25), Color(hex: "D97706").opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(hex: "F59E0B").opacity(0.4), lineWidth: 1)
                    )
                
                Image(systemName: "note.text")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Color(hex: "F59E0B"))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Ghi chú mép màn hình (Screen Edge Notes)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Liquid Glass")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "F59E0B"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "F59E0B").opacity(0.15)))
                }
                
                Text("Rê chuột ra mép phải là mở, gõ là tự lưu, rê ra ngoài là tự ẩn. Tích hợp đồng bộ mượt mà với Apple Notes iCloud.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Toggle Drawer Button
            Button(action: {
                drawer.toggleDrawer()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: drawer.isVisible ? "sidebar.right" : "arrow.left.to.line")
                    Text(drawer.isVisible ? "Đóng ngăn kéo" : "Mở ngăn kéo ngay")
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color(hex: "F59E0B").opacity(0.85))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
    
    // MARK: - 2. Edge Trigger Section
    
    private var edgeTriggerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CỬ CHỈ & PHÍM TẮT MỞ NHANH")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            VStack(spacing: 0) {
                // Toggle Row: Hover to Peek
                HStack(spacing: 12) {
                    Image(systemName: "hand.point.right.fill")
                        .font(.system(size: 16))
                        .foregroundColor(hotspot.isEdgeTriggerEnabled ? Color(hex: "F59E0B") : .white.opacity(0.4))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rê chuột mép phải để mở (Hover to Peek)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Chạm chuột vào mép phải màn hình 130ms để mở ngăn kéo ghi chú tức thì")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $hotspot.isEdgeTriggerEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "F59E0B")))
                        .labelsHidden()
                }
                .padding(14)
                
                Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
                
                // Shortcut Row: ⌥N
                HStack(spacing: 12) {
                    Image(systemName: "command")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phím tắt toàn cục")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Nhấn phím tắt ở bất kỳ đâu để bật hoặc đóng ngăn kéo")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    
                    Spacer()
                    
                    Text("⌥N (Option + N)")
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        )
                }
                .padding(14)
                
                Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
                
                // Pin Mode Info
                HStack(spacing: 12) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 14))
                        .foregroundColor(drawer.isPinned ? Color(hex: "F59E0B") : .white.opacity(0.5))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chế độ Ghim cửa sổ (Pin Mode)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text(drawer.isPinned ? "Hiện tại đang ghim: cửa sổ không tự ẩn khi rê chuột ra ngoài" : "Bấm nút 📌 trên thanh tiêu đề để giữ cửa sổ khi tra cứu tài liệu")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    
                    Spacer()
                    
                    Button(drawer.isPinned ? "Bỏ ghim" : "Ghim") {
                        drawer.isPinned.toggle()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(drawer.isPinned ? Color(hex: "F59E0B") : .white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(drawer.isPinned ? Color(hex: "F59E0B").opacity(0.15) : Color.white.opacity(0.05))
                    )
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
            )
        }
    }
    
    // MARK: - 3. Apple Notes Cloud Sync Section
    
    private var appleNotesSyncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ĐỒNG BỘ CLOUD VỚI APPLE NOTES (ICLOUD)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            VStack(spacing: 0) {
                // Auto Sync Toggle
                HStack(spacing: 12) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 16))
                        .foregroundColor(syncEngine.isAutoSyncEnabled ? Color.white : .white.opacity(0.4))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Tự động đồng bộ vào Apple Notes")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Circle()
                                .fill(syncEngine.isSyncing ? Color(hex: "F59E0B") : (syncEngine.isAutoSyncEnabled ? Color(hex: "10B981") : Color.gray))
                                .frame(width: 6, height: 6)
                        }
                        
                        Text("Tạo và cập nhật ghi chú trong thư mục 'CFinder Quick Notes', đồng bộ qua iPhone/iPad/Mac")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $syncEngine.isAutoSyncEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: Color(hex: "F59E0B")))
                        .labelsHidden()
                }
                .padding(14)
                
                Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
                
                // Status & Open Notes Button
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trạng thái kết nối:")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(syncEngine.syncStatusText)
                            .font(.system(size: 11))
                            .foregroundColor(syncEngine.isSyncing ? Color(hex: "F59E0B") : Color(hex: "10B981"))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        syncEngine.openAppleNotesApp()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Mở  Notes.app")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
            )
        }
    }
    
    // MARK: - 4. Notes Overview Section
    
    private var notesOverviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LƯU TRỮ CỤC BỘ & DANH SÁCH GHI CHÚ")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.35))
            
            HStack(spacing: 12) {
                // Metric 1: Số lượng ghi chú
                storageMetricCard(
                    title: "Tổng số ghi chú",
                    value: "\(storage.notes.count)",
                    icon: "doc.on.doc.fill",
                    color: Color(hex: "38BDF8")
                )
                
                // Metric 2: Ghi chú hiện tại
                storageMetricCard(
                    title: "Ghi chú hiện tại",
                    value: storage.currentNote.mode == .text ? "Văn bản" : "Việc cần làm",
                    icon: storage.currentNote.mode == .text ? "text.alignleft" : "checklist",
                    color: Color(hex: "10B981")
                )
                
                // Metric 3: Đã lưu an toàn
                storageMetricCard(
                    title: "Trạng thái",
                    value: storage.isSaving ? "Đang lưu..." : "Đã lưu an toàn",
                    icon: "checkmark.shield.fill",
                    color: Color(hex: "F59E0B")
                )
            }
            
            // Storage Location & Open Folder
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                
                Text("Vị trí: ~/Library/Application Support/CFinder/Notes/notes.json")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                
                Spacer()
                
                Button("Mở thư mục") {
                    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    let dir = appSupport.appendingPathComponent("CFinder/Notes", isDirectory: true)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.02))
            )
        }
    }
    
    private func storageMetricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.05), lineWidth: 1))
        )
    }
}
