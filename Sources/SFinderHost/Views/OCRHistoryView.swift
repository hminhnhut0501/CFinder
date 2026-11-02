import SwiftUI
import AppKit
import SFinderCore

public struct OCRHistoryView: View {
    @State private var entries: [OCRHistoryEntry] = ScreenOCREngine.shared.fullHistory
    @State private var searchText: String = ""
    @State private var selectedEntryID: UUID?
    @State private var editedText: String = ""
    @State private var copyFeedback: Bool = false
    
    private var filteredEntries: [OCRHistoryEntry] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entries
        }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var selectedEntry: OCRHistoryEntry? {
        guard let id = selectedEntryID else { return filteredEntries.first }
        return entries.first(where: { $0.id == id }) ?? filteredEntries.first
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.orange)
                
                Text("Lịch sử quét chữ OCR (\(entries.count))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 12))
                    TextField("Tìm kiếm văn bản...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(width: 200)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                
                // Clear all button
                if !entries.isEmpty {
                    Button(action: clearAll) {
                        Text("Xoá tất cả")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.03))
            
            Divider().background(Color.white.opacity(0.1))
            
            // Main split view (List on left, Detail/Editor on right)
            if entries.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    // Left list of clippings
                    VStack(spacing: 0) {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredEntries) { entry in
                                    HistoryEntryRow(
                                        entry: entry,
                                        isSelected: entry.id == selectedEntry?.id
                                    ) {
                                        selectedEntryID = entry.id
                                        editedText = entry.text
                                    }
                                }
                            }
                            .padding(10)
                        }
                    }
                    .frame(minWidth: 260, maxWidth: 340)
                    .background(Color.white.opacity(0.02))
                    
                    // Right detail editor
                    VStack(alignment: .leading, spacing: 12) {
                        if let current = selectedEntry {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formattedDate(current.timestamp))
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.5))
                                    Text("\(editedText.count) ký tự")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                
                                Spacer()
                                
                                if current.isURL {
                                    Button(action: {
                                        if let u = URL(string: editedText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                            NSWorkspace.shared.open(u)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "safari")
                                            Text("Mở URL")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.cyan)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.cyan.opacity(0.15)))
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Button(action: { copyToClipboard(text: editedText) }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                                        Text(copyFeedback ? "Đã chép!" : "Sao chép")
                                    }
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.orange))
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { deleteEntry(id: current.id) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red.opacity(0.8))
                                        .padding(6)
                                        .background(Circle().fill(Color.red.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // Text Editor
                            TextEditor(text: $editedText)
                                .font(.system(size: 13, weight: .regular, design: current.isTable ? .monospaced : .default))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                        } else {
                            VStack {
                                Spacer()
                                Text("Chọn một đoạn trích bên trái để xem nội dung")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(16)
                    .frame(minWidth: 320)
                }
            }
        }
        .frame(width: 720, height: 480)
        .background(
            ZStack {
                Color(red: 0.10, green: 0.11, blue: 0.15)
                RadialGradient(
                    colors: [Color.orange.opacity(0.08), Color.clear],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 350
                )
            }
        )
        .onAppear {
            if let first = entries.first {
                selectedEntryID = first.id
                editedText = first.text
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.25))
            Text("Chưa có lịch sử quét văn bản")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Text("Nhấn ⌥C (hoặc quét từ Menu bar) để quét chữ bất kỳ trên màn hình.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyFeedback = false
        }
    }
    
    private func deleteEntry(id: UUID) {
        ScreenOCREngine.shared.deleteHistoryEntry(id: id)
        entries = ScreenOCREngine.shared.fullHistory
        if selectedEntryID == id {
            selectedEntryID = entries.first?.id
            editedText = entries.first?.text ?? ""
        }
    }
    
    private func clearAll() {
        ScreenOCREngine.shared.clearHistory()
        entries = []
        selectedEntryID = nil
        editedText = ""
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm, dd/MM/yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - History Row Component

struct HistoryEntryRow: View {
    let entry: OCRHistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var snippet: String {
        let clean = entry.text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        return clean.count > 60 ? String(clean.prefix(60)) + "..." : clean
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if entry.isURL {
                        Text("URL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.cyan.opacity(0.2)))
                    }
                    if entry.isTable {
                        Text("BẢNG")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                    }
                    Text("\(entry.text.count) ký tự")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Spacer()
                    
                    Text(timeAgo(entry.timestamp))
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Text(snippet)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.orange.opacity(0.25) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func timeAgo(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "vừa xong" }
        if diff < 3600 { return "\(diff / 60)m trước" }
        if diff < 86400 { return "\(diff / 3600)h trước" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: date)
    }
}
