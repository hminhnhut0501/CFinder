import SwiftUI
import AppKit
import SFinderCore

public struct EdgeNotesDrawerView: View {
    @ObservedObject var controller: EdgeNotesWindowController
    @ObservedObject private var storage = QuickNotesStorage.shared
    @ObservedObject private var syncEngine = AppleNotesSyncEngine.shared
    
    @State private var newChecklistText: String = ""
    @FocusState private var isChecklistInputFocused: Bool
    @FocusState private var isTitleFocused: Bool
    
    public init(controller: EdgeNotesWindowController) {
        self.controller = controller
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header Bar (Clean 1-line layout)
            headerBar
            
            Divider().background(Color.white.opacity(0.08))
            
            // MARK: - Title Input Row (1-line)
            titleInputRow
            
            Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 14)
            
            // MARK: - Note Content Area (Text or Checklist)
            if storage.currentNote.mode == .text {
                textEditorView
            } else {
                checklistEditorView
            }
            
            Divider().background(Color.white.opacity(0.08))
            
            // MARK: - Bottom Toolbar & Sync Status
            bottomToolbar
        }
        .frame(width: 380)
        .background(
            ZStack {
                // Liquid Glass Obsidian Base (Solid clean background, no clipped shadow)
                Color(hex: "131418").opacity(0.97)
                
                // Subtle radial ambience
                RadialGradient(
                    colors: [CFinderTheme.primary.opacity(0.07), Color.clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 260
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    controller.isPinned ? Color(hex: "F59E0B").opacity(0.4) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
        )
        .onHover { isInside in
            if isInside {
                controller.handleMouseEnteredDrawer()
            } else {
                controller.handleMouseExitedDrawer()
            }
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 8) {
            // Mode Switcher (Strictly 1-line Segmented Pill)
            HStack(spacing: 2) {
                modeSegmentButton(title: "Ghi chú", icon: "doc.text", mode: .text)
                modeSegmentButton(title: "Việc làm", icon: "checklist", mode: .checklist)
            }
            .padding(2.5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))
            
            Spacer()
            
            // Clean Icon Buttons Row
            HStack(spacing: 6) {
                // 1. Pin Toggle (Icon only)
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        controller.isPinned.toggle()
                    }
                }) {
                    Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(controller.isPinned ? Color(hex: "F59E0B") : .white.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(controller.isPinned ? Color(hex: "F59E0B").opacity(0.18) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(controller.isPinned ? Color(hex: "F59E0B").opacity(0.35) : Color.clear, lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(controller.isPinned ? "Đang ghim (Cửa sổ không tự ẩn khi rê chuột ra ngoài)" : "Ghim cửa sổ để không tự ẩn")
                
                // 2. Apple Notes Sync / Open (Icon only)
                Button(action: {
                    syncEngine.performSync(note: storage.currentNote)
                    syncEngine.openAppleNotesApp()
                }) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 12))
                        .foregroundColor(CFinderTheme.primaryLight.opacity(0.9))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(CFinderTheme.primary.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(CFinderTheme.primary.opacity(0.25), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("Mở thư mục CFinder Quick Notes trong Apple Notes")
                
                // 3. New Note (+)
                Button(action: {
                    withAnimation {
                        storage.createNewNote(mode: storage.currentNote.mode)
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .help("Tạo ghi chú mới")
                
                // 4. Close (✕)
                Button(action: {
                    controller.hideDrawer(force: true)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .help("Đóng ngăn kéo (Esc)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    
    private func modeSegmentButton(title: String, icon: String, mode: QuickNoteMode) -> some View {
        let isSelected = storage.currentNote.mode == mode
        return Button(action: {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                storage.currentNote.mode = mode
                storage.requestAutoSave()
                syncEngine.requestSync(note: storage.currentNote)
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Title Input Row
    
    private var titleInputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12))
                .foregroundColor(CFinderTheme.primaryLight.opacity(0.8))
            
            TextField("Tiêu đề ghi chú...", text: $storage.currentNote.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($isTitleFocused)
                .onChange(of: storage.currentNote.title) { _ in
                    storage.requestAutoSave()
                    syncEngine.requestSync(note: storage.currentNote)
                }
            
            if !storage.currentNote.title.isEmpty {
                Button(action: {
                    storage.currentNote.title = ""
                    storage.requestAutoSave()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Xoá tiêu đề")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
    
    // MARK: - Text Mode Editor
    
    private var textEditorView: some View {
        ZStack(alignment: .topLeading) {
            if storage.currentNote.bodyText.isEmpty {
                Text("Gõ nội dung ghi chú ở đây...\n(Tự động lưu ngay lập tức • Hỗ trợ phím tắt ⌥N)")
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.28))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            
            TextEditor(text: $storage.currentNote.bodyText)
                .font(.system(size: 12.5, design: .default))
                .foregroundColor(.white.opacity(0.92))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .onChange(of: storage.currentNote.bodyText) { _ in
                    storage.requestAutoSave()
                    syncEngine.requestSync(note: storage.currentNote)
                }
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Checklist Mode Editor
    
    private var checklistEditorView: some View {
        VStack(spacing: 8) {
            // New Todo Item Input Row
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(CFinderTheme.primaryLight)
                
                TextField("Thêm việc cần làm (nhấn Enter)...", text: $newChecklistText)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .focused($isChecklistInputFocused)
                    .onSubmit {
                        addChecklistItem()
                    }
                
                if !newChecklistText.isEmpty {
                    Button(action: addChecklistItem) {
                        Text("Thêm")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(CFinderTheme.primary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            
            // Checklist Items ScrollView
            ScrollView {
                VStack(spacing: 6) {
                    if storage.currentNote.checklist.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checklist.checked")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.2))
                            Text("Chưa có mục việc nào\nNhập ở trên và bấm Enter để thêm việc mới")
                                .font(.system(size: 11))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        ForEach($storage.currentNote.checklist) { $item in
                            checklistItemRow(item: $item)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func checklistItemRow(item: Binding<QuickChecklistItem>) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    item.wrappedValue.isCompleted.toggle()
                    storage.requestAutoSave()
                    syncEngine.requestSync(note: storage.currentNote)
                }
            }) {
                Image(systemName: item.wrappedValue.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(item.wrappedValue.isCompleted ? Color(hex: "10B981") : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            TextField("", text: item.text)
                .font(.system(size: 12))
                .strikethrough(item.wrappedValue.isCompleted, color: .white.opacity(0.4))
                .foregroundColor(item.wrappedValue.isCompleted ? .white.opacity(0.4) : .white.opacity(0.9))
                .textFieldStyle(.plain)
                .lineLimit(1)
                .onChange(of: item.wrappedValue.text) { _ in
                    storage.requestAutoSave()
                    syncEngine.requestSync(note: storage.currentNote)
                }
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    storage.currentNote.checklist.removeAll(where: { $0.id == item.wrappedValue.id })
                    storage.requestAutoSave()
                    syncEngine.requestSync(note: storage.currentNote)
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(item.wrappedValue.isCompleted ? 0.02 : 0.04))
        )
    }
    
    private func addChecklistItem() {
        let trimmed = newChecklistText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            storage.currentNote.checklist.append(QuickChecklistItem(text: trimmed, isCompleted: false))
            newChecklistText = ""
            storage.requestAutoSave()
            syncEngine.requestSync(note: storage.currentNote)
        }
    }
    
    // MARK: - Bottom Toolbar
    
    private var bottomToolbar: some View {
        HStack(spacing: 8) {
            // Live Status Indicator Dot
            HStack(spacing: 5) {
                Circle()
                    .fill(syncEngine.isSyncing ? Color(hex: "F59E0B") : Color(hex: "10B981"))
                    .frame(width: 6, height: 6)
                
                Text(syncEngine.isSyncing ? "Đang lưu..." : syncEngine.syncStatusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Format quick shortcuts (for Text mode)
            if storage.currentNote.mode == .text {
                HStack(spacing: 5) {
                    formatButton(label: "B", snippet: "****")
                    formatButton(label: "I", snippet: "**")
                    formatButton(label: "•", snippet: "\n• ")
                    formatButton(label: "#", snippet: "\n## ")
                }
            } else {
                Text("\(storage.currentNote.completedChecklistCount)/\(storage.currentNote.checklist.count) hoàn thành")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "10B981"))
                    .lineLimit(1)
            }
            
            Text("• \(storage.currentNote.wordCount) từ")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02))
    }
    
    private func formatButton(label: String, snippet: String) -> some View {
        Button(action: {
            storage.currentNote.bodyText += snippet
            storage.requestAutoSave()
        }) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
