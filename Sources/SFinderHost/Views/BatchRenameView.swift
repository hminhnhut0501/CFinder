import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SFinderCore

public struct BatchRenameView: View {
    public let onDismiss: () -> Void
    
    @State private var currentURLs: [URL]
    @State private var rule = RenameRule.loadLastUsed()
    @State private var previews: [RenamePreviewItem] = []
    @State private var statusMessage: String?
    @State private var isSuccess: Bool = false
    @State private var isApplying: Bool = false
    @State private var searchText: String = ""
    @State private var isDropTargeted: Bool = false
    @State private var ambientPulse: Bool = false
    @State private var emptyIconBounce: Bool = false
    @State private var showPrefixBlock: Bool = false
    @State private var showSuffixBlock: Bool = false
    @State private var showTrimBlock: Bool = false
    @State private var showFindReplaceBlock: Bool = false
    
    public init(urls: [URL], onDismiss: @escaping () -> Void) {
        self._currentURLs = State(initialValue: urls)
        self.onDismiss = onDismiss
    }
    
    private var changedCount: Int {
        previews.filter { $0.isChanged && !$0.hasCollision }.count
    }
    
    private var collisionCount: Int {
        previews.filter { $0.hasCollision }.count
    }
    
    private var filteredPreviews: [RenamePreviewItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return previews
        }
        return previews.filter {
            $0.originalName.localizedCaseInsensitiveContains(searchText) ||
            $0.newName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    public var body: some View {
        ZStack {
            // MARK: - Native Apple Liquid Glass Background
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()
            
            // Living Ambient Glows for dynamic Liquid Glass depth
            VStack {
                HStack {
                    Circle()
                        .fill(CFinderTheme.FeatureColor.rename.opacity(ambientPulse ? 0.15 : 0.08))
                        .frame(width: ambientPulse ? 360 : 310, height: ambientPulse ? 360 : 310)
                        .blur(radius: 65)
                        .offset(x: ambientPulse ? -60 : -90, y: ambientPulse ? -40 : -70)
                    Spacer()
                    Circle()
                        .fill(Color(hex: "A855F7").opacity(ambientPulse ? 0.12 : 0.06))
                        .frame(width: ambientPulse ? 320 : 270, height: ambientPulse ? 320 : 270)
                        .blur(radius: 65)
                        .offset(x: ambientPulse ? 70 : 90, y: ambientPulse ? -20 : -50)
                }
                Spacer()
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true), value: ambientPulse)
            
            // MARK: - Main Layout
            VStack(spacing: 0) {
                headerBar
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                controlPanelArea
                fileListArea
                footerBar
            }
        }
        .frame(minWidth: 960, idealWidth: 1020, minHeight: 640, idealHeight: 700)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDropTargeted ? 0.7 : 0.28),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        )
        .overlay(
            Group {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [CFinderTheme.primary, Color(hex: "BF5AF2"), Color(hex: "5E5CE6")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, dash: [8, 5])
                        )
                        .background(Color.blue.opacity(0.08))
                        .transition(.opacity)
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: rule) { _, newRule in
            newRule.saveAsLastUsed()
            updatePreview()
        }
        .onAppear {
            if !rule.prefix.isEmpty { showPrefixBlock = true }
            if !rule.suffix.isEmpty { showSuffixBlock = true }
            if rule.deleteFirstN > 0 || rule.deleteLastN > 0 { showTrimBlock = true }
            if !rule.findText.isEmpty { showFindReplaceBlock = true }
            updatePreview()
            ambientPulse = true
        }
    }
    
    // MARK: - 1. Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Squircle Brand Badge (Dashboard style)
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CFinderTheme.FeatureColor.rename.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(CFinderTheme.FeatureColor.rename.opacity(0.28), lineWidth: 1)
                    )
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CFinderTheme.FeatureColor.rename)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Đổi tên tệp hàng loạt")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text("STUDIO")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(LinearGradient(colors: [CFinderTheme.FeatureColor.rename, Color(hex: "A855F7")], startPoint: .leading, endPoint: .trailing))
                        )
                        .foregroundColor(.white)
                }
                .fixedSize(horizontal: true, vertical: false)
                
                Text(currentURLs.isEmpty ? "Đổi tên nhanh và an toàn trên macOS Finder" : "\(currentURLs.count) tệp được nạp")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            // Search / Filter inside list (Compact)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.45))
                    .font(.system(size: 11))
                TextField("Lọc tệp...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.45))
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(.horizontal, 7)
            .frame(width: 120, height: 28)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Add files button (Compact Icon + Label)
            Button(action: handleChooseFiles) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Thêm tệp")
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Thêm tệp vào danh sách đổi tên")
            
            // Clear files button (Icon-only with tooltip)
            if !currentURLs.isEmpty {
                Button(action: handleClearFiles) {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color(hex: "F43F5E"))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: "F43F5E").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color(hex: "F43F5E").opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Xóa toàn bộ tệp trong danh sách về trạng thái trống")
            }
            
            // Reset rule button (Icon-only)
            Button(action: handleResetFormat) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Khôi phục toàn bộ tùy chọn đổi tên về mặc định")
            
            // Undo button (Icon-only)
            Button(action: handleUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Hoàn tác lượt đổi tên gần nhất (⌘Z)")
            
            // Dashboard-style Circular Close Button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.04))
                            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Đóng cửa sổ")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.015))
    }
    
    // MARK: - 2. Token Recipe Studio Area (Khối ghép công thức đổi tên thông minh)
    
    private var controlPanelArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            RecipeChainScrollView(
                rule: $rule,
                showPrefixBlock: $showPrefixBlock,
                showSuffixBlock: $showSuffixBlock,
                showTrimBlock: $showTrimBlock,
                showFindReplaceBlock: $showFindReplaceBlock
            )
            
            Divider().opacity(0.12)
            
            RecipeQuickUtilitiesBar(
                rule: $rule,
                onReset: handleResetFormat
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 12, strokeOpacity: 0.15, fillOpacity: 0.04)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
    
    // MARK: - 4. Live Diff Preview List
    
    private var fileListArea: some View {
        VStack(spacing: 0) {
            // Table Header Bar
            HStack(spacing: 12) {
                Text("TÊN GỐC HIỆN TẠI")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(.clear)
                
                Text("TÊN MỚI DỰ KIẾN (LIVE DIFF)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("TRẠNG THÁI")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 110, alignment: .trailing)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 6)
            
            if currentURLs.isEmpty {
                emptyDropStateView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredPreviews) { item in
                            RenameFileRowView(item: item)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: currentURLs.isEmpty)
    }
    
    private var emptyDropStateView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [CFinderTheme.primary.opacity(0.18), Color(hex: "BF5AF2").opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: emptyIconBounce ? 90 : 82, height: emptyIconBounce ? 90 : 82)
                    .shadow(color: Color.blue.opacity(0.2), radius: 15, y: 5)
                
                Image(systemName: "pencil.and.list.clipboard")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(CFinderTheme.primary)
                    .offset(y: emptyIconBounce ? -2 : 2)
            }
            .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: emptyIconBounce)
            .onAppear {
                emptyIconBounce = true
            }
            
            VStack(spacing: 4) {
                Text("Kéo thả tệp hoặc thư mục vào đây")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                
                Text("Hoặc bấm nút 'Thêm tệp' ở góc trên để chọn tệp cần đổi tên.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Button("Chọn tệp trên Mac...") {
                handleChooseFiles()
            }
            .buttonStyle(.borderedProminent)
            .focusable(false)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    // MARK: - 5. Floating Bottom Action Hub
    
    private var footerBar: some View {
        RenameFooterBarView(
            totalCount: currentURLs.count,
            changedCount: changedCount,
            collisionCount: collisionCount,
            statusMessage: statusMessage,
            isSuccess: isSuccess,
            isApplying: isApplying,
            onDismiss: onDismiss,
            onApply: handleApply
        )
    }
    
    // MARK: - Helpers
    
    private func glassInputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            HStack {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                
                if !text.wrappedValue.isEmpty {
                    Button(action: { text.wrappedValue = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.12), lineWidth: 0.6))
        }
    }
    
    private func updatePreview() {
        self.previews = BatchRenameEngine.shared.generatePreview(urls: currentURLs, rule: rule)
    }
    
    private func handleChooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Chọn tệp đổi tên"
        panel.level = .floating
        if panel.runModal() == .OK {
            var picked: [URL] = []
            for u in panel.urls {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    if let contents = try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                        let files = contents.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                        picked.append(contentsOf: files)
                    }
                } else {
                    picked.append(u)
                }
            }
            if !picked.isEmpty {
                let existingSet = Set(currentURLs.map { $0.path })
                for p in picked where !existingSet.contains(p.path) {
                    currentURLs.append(p)
                }
                currentURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                updatePreview()
            }
        }
    }
    
    private func handleApply() {
        isApplying = true
        statusMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let record = try BatchRenameEngine.shared.applyRename(items: self.previews)
                DispatchQueue.main.async {
                    self.isApplying = false
                    self.isSuccess = true
                    self.statusMessage = "Đã đổi tên thành công \(record.entries.count) tệp!"
                    // Clean list after renaming so opening again starts with empty list
                    self.currentURLs = []
                    self.updatePreview()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        onDismiss()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isApplying = false
                    self.isSuccess = false
                    self.statusMessage = "Lỗi: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleClearFiles() {
        withAnimation(.easeInOut(duration: 0.2)) {
            currentURLs.removeAll()
            previews.removeAll()
            statusMessage = "Đã làm sạch danh sách tệp"
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var droppedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                            let files = contents.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                            droppedURLs.append(contentsOf: files)
                        }
                    } else {
                        droppedURLs.append(url)
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if !droppedURLs.isEmpty {
                let existingSet = Set(currentURLs.map { $0.path })
                for u in droppedURLs where !existingSet.contains(u.path) {
                    currentURLs.append(u)
                }
                currentURLs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                updatePreview()
            }
        }
        return true
    }
    
    private func handleUndo() {
        do {
            if let reverted = try RenameUndoJournal.shared.undoLast(), !reverted.isEmpty {
                self.isSuccess = true
                self.statusMessage = "Đã hoàn tác \(reverted.count) tệp về tên cũ!"
                self.currentURLs = reverted.map { URL(fileURLWithPath: $0.originalPath) }
                updatePreview()
            } else {
                self.isSuccess = false
                self.statusMessage = "Không có thao tác nào trước đó để hoàn tác."
            }
        } catch {
            self.isSuccess = false
            self.statusMessage = "Lỗi hoàn tác: \(error.localizedDescription)"
        }
    }
    
    private func handleResetFormat() {
        RenameRule.resetToDefault()
        self.rule = RenameRule()
        self.rule.clearOriginalName = false
        self.rule.customBaseName = ""
        self.showPrefixBlock = false
        self.showSuffixBlock = false
        self.showTrimBlock = false
        self.showFindReplaceBlock = false
        self.statusMessage = "Đã đặt lại quy tắc đổi tên về mặc định"
        self.isSuccess = true
        updatePreview()
    }
}

// MARK: - Recipe Studio Block Views

struct RecipeChainScrollView: View {
    @Binding var rule: RenameRule
    @Binding var showPrefixBlock: Bool
    @Binding var showSuffixBlock: Bool
    @Binding var showTrimBlock: Bool
    @Binding var showFindReplaceBlock: Bool
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                rootBlock
                dateBlock
                trimBlock
                prefixBlock
                numberingBlock
                suffixBlock
                findReplaceBlock
                addBlock
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
        }
    }
    
    @ViewBuilder
    private var rootBlock: some View {
        RecipeRootControlView(
            clearOriginalName: $rule.clearOriginalName,
            customBaseName: $rule.customBaseName
        )
        recipeArrow
    }
    
    @ViewBuilder
    private var dateBlock: some View {
        if rule.enableDatePrefix {
            RecipeDateBlockView(
                isEnabled: $rule.enableDatePrefix,
                format: $rule.datePrefixFormat
            )
            recipeArrow
        }
    }
    
    @ViewBuilder
    private var trimBlock: some View {
        if rule.deleteFirstN > 0 || rule.deleteLastN > 0 || showTrimBlock {
            RecipeTrimCharsBlockView(
                deleteFirstN: $rule.deleteFirstN,
                deleteLastN: $rule.deleteLastN,
                onClose: {
                    rule.deleteFirstN = 0
                    rule.deleteLastN = 0
                    showTrimBlock = false
                }
            )
            recipeArrow
        }
    }
    
    @ViewBuilder
    private var prefixBlock: some View {
        if !rule.prefix.isEmpty || showPrefixBlock {
            RecipePrefixBlockView(
                prefix: $rule.prefix,
                onClose: {
                    rule.prefix = ""
                    showPrefixBlock = false
                }
            )
            recipeArrow
        }
    }
    
    @ViewBuilder
    private var numberingBlock: some View {
        if rule.enableNumbering {
            RecipeNumberingBlockView(
                isEnabled: $rule.enableNumbering,
                format: $rule.numberingFormat,
                position: $rule.numberingPosition,
                startNumber: $rule.startNumber,
                separator: $rule.numberingSeparator
            )
            recipeArrow
        }
    }
    
    @ViewBuilder
    private var suffixBlock: some View {
        if !rule.suffix.isEmpty || showSuffixBlock {
            RecipeSuffixBlockView(
                suffix: $rule.suffix,
                onClose: {
                    rule.suffix = ""
                    showSuffixBlock = false
                }
            )
            recipeArrow
        }
    }
    
    @ViewBuilder
    private var findReplaceBlock: some View {
        if !rule.findText.isEmpty || showFindReplaceBlock {
            RecipeFindReplaceBlockView(
                findText: $rule.findText,
                replaceText: $rule.replaceText,
                isRegex: $rule.isRegex,
                matchCase: $rule.matchCase,
                onClose: {
                    rule.findText = ""
                    rule.replaceText = ""
                    showFindReplaceBlock = false
                }
            )
            recipeArrow
        }
    }
    
    private var addBlock: some View {
        RecipeAddBlockMenu(
            rule: $rule,
            showPrefixBlock: $showPrefixBlock,
            showSuffixBlock: $showSuffixBlock,
            showTrimBlock: $showTrimBlock,
            showFindReplaceBlock: $showFindReplaceBlock
        )
    }
    
    private var recipeArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(.white.opacity(0.25))
    }
}

struct RecipeRootControlView: View {
    @Binding var clearOriginalName: Bool
    @Binding var customBaseName: String
    
    var body: some View {
        HStack(spacing: 5) {
            Menu {
                Button(action: {
                    clearOriginalName = false
                    customBaseName = ""
                }) {
                    Label("Giữ nguyên tên gốc", systemImage: "doc.text")
                }
                
                Button(action: {
                    clearOriginalName = true
                }) {
                    Label("Xóa sạch tên cũ", systemImage: "trash")
                }
                
                Divider()
                
                Button(action: {
                    clearOriginalName = true
                    if customBaseName.isEmpty { customBaseName = "Item" }
                }) {
                    Label("Đặt tên cơ sở mới...", systemImage: "pencil")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: clearOriginalName ? "trash.fill" : "doc.text.fill")
                        .font(.system(size: 10.5, weight: .bold))
                    Text(clearOriginalName ? "Xóa tên cũ" : "Giữ tên gốc")
                        .font(.system(size: 11, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .opacity(0.6)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    clearOriginalName
                        ? Color(hex: "F43F5E").opacity(0.22)
                        : Color.white.opacity(0.08)
                )
                .foregroundColor(clearOriginalName ? Color(hex: "F43F5E") : .white)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            clearOriginalName ? Color(hex: "F43F5E").opacity(0.4) : Color.white.opacity(0.18),
                            lineWidth: 1
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Khối #1: Chọn giữ tên gốc hoặc xóa sạch tên cũ để đánh số/ngày")
            
            if clearOriginalName {
                HStack(spacing: 3) {
                    TextField("Tên mới...", text: $customBaseName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .frame(width: 90)
                    if !customBaseName.isEmpty {
                        Button(action: { customBaseName = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4.5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                .help("Tùy chọn: Nhập tên cơ sở thay thế tên gốc hoặc để trống")
            }
        }
    }
}

struct RecipeDateBlockView: View {
    @Binding var isEnabled: Bool
    @Binding var format: DatePrefixFormat
    
    var body: some View {
        HStack(spacing: 5) {
            Menu {
                ForEach(DatePrefixFormat.allCases, id: \.self) { fmt in
                    Button(action: { format = fmt }) {
                        HStack {
                            Text(fmt.rawValue)
                            if format == fmt { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4.5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(CFinderTheme.FeatureColor.rename)
                    
                    Text("Ngày:")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                    
                    Text(format.formatted())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(CFinderTheme.FeatureColor.rename)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .opacity(0.5)
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .padding(.vertical, 4.5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Button(action: { isEnabled = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Gỡ khối Ngày")
        }
        .background(CFinderTheme.FeatureColor.rename.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(CFinderTheme.FeatureColor.rename.opacity(0.32), lineWidth: 0.9))
    }
}

struct RecipeTrimCharsBlockView: View {
    @Binding var deleteFirstN: Int
    @Binding var deleteLastN: Int
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "scissors")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.orange)
                .padding(.leading, 8)
            
            Text("Cắt:")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            
            HStack(spacing: 3) {
                Text("Đầu")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                NumberInputField(value: $deleteFirstN, range: 0...999)
                    .frame(width: 50)
            }
            
            HStack(spacing: 3) {
                Text("Đuôi")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                NumberInputField(value: $deleteLastN, range: 0...999)
                    .frame(width: 50)
            }
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Gỡ khối Cắt ký tự")
        }
        .padding(.vertical, 3.5)
        .background(Color.orange.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 0.9))
    }
}

struct RecipePrefixBlockView: View {
    @Binding var prefix: String
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "text.insert")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "06B6D4"))
                .padding(.leading, 8)
            
            Text("Tiền tố:")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            
            TextField("TG@...", text: $prefix)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .frame(minWidth: 80, maxWidth: 140)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.12), lineWidth: 0.6))
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Gỡ khối Tiền tố")
        }
        .padding(.vertical, 3.5)
        .background(Color(hex: "06B6D4").opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "06B6D4").opacity(0.3), lineWidth: 0.9))
    }
}

struct RecipeNumberingBlockView: View {
    @Binding var isEnabled: Bool
    @Binding var format: NumberingFormat
    @Binding var position: NumberingPosition
    @Binding var startNumber: Int
    @Binding var separator: String
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "number")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "8B5CF6"))
                .padding(.leading, 8)
            
            Text("Đánh số:")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            
            Menu {
                ForEach(NumberingFormat.allCases, id: \.self) { fmt in
                    Button(action: { format = fmt }) {
                        HStack {
                            Text(fmt.rawValue)
                            if format == fmt { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(format.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7.5, weight: .bold))
                        .opacity(0.6)
                }
                .foregroundColor(Color(hex: "8B5CF6"))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Menu {
                ForEach(NumberingPosition.allCases, id: \.self) { pos in
                    Button(action: { position = pos }) {
                        HStack {
                            Text(pos.rawValue)
                            if position == pos { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(position == .prefix ? "Đầu tên" : (position == .suffix ? "Cuối tên" : "Chỉ số"))
                        .font(.system(size: 10.5, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .opacity(0.6)
                }
                .foregroundColor(.white.opacity(0.85))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            HStack(spacing: 2) {
                Text("từ")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                NumberInputField(value: $startNumber, range: 0...999999)
                    .frame(width: 48)
            }
            
            Button(action: { isEnabled = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Gỡ khối Đánh số")
        }
        .padding(.vertical, 3.5)
        .background(Color(hex: "8B5CF6").opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "8B5CF6").opacity(0.3), lineWidth: 0.9))
    }
}

struct RecipeSuffixBlockView: View {
    @Binding var suffix: String
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "text.append")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "3B82F6"))
                .padding(.leading, 8)
            
            Text("Hậu tố:")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            
            TextField("_v1...", text: $suffix)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .frame(minWidth: 80, maxWidth: 140)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.12), lineWidth: 0.6))
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Gỡ khối Hậu tố")
        }
        .padding(.vertical, 3.5)
        .background(Color(hex: "3B82F6").opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "3B82F6").opacity(0.3), lineWidth: 0.9))
    }
}

struct RecipeFindReplaceBlockView: View {
    @Binding var findText: String
    @Binding var replaceText: String
    @Binding var isRegex: Bool
    @Binding var matchCase: Bool
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "10B981"))
                .padding(.leading, 8)
            
            TextField("Tìm...", text: $findText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 75)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
            
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            
            TextField("Thay...", text: $replaceText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .frame(width: 75)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
            
            Button(action: { matchCase.toggle() }) {
                Text("Aa")
                    .font(.system(size: 9.5, weight: matchCase ? .bold : .regular))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(matchCase ? Color(hex: "10B981").opacity(0.3) : Color.white.opacity(0.06))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Khớp chữ Hoa/thường")
            
            Button(action: { isRegex.toggle() }) {
                Text(".*")
                    .font(.system(size: 9.5, weight: isRegex ? .bold : .regular, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isRegex ? Color(hex: "10B981").opacity(0.3) : Color.white.opacity(0.06))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Biểu thức Regex")
            
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(3)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Gỡ khối Tìm & Thay thế")
        }
        .padding(.vertical, 3.5)
        .background(Color(hex: "10B981").opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "10B981").opacity(0.3), lineWidth: 0.9))
    }
}

struct RecipeAddBlockMenu: View {
    @Binding var rule: RenameRule
    @Binding var showPrefixBlock: Bool
    @Binding var showSuffixBlock: Bool
    @Binding var showTrimBlock: Bool
    @Binding var showFindReplaceBlock: Bool
    
    var body: some View {
        Menu {
            Button(action: {
                withAnimation { rule.enableDatePrefix = true }
            }) {
                Label("Thêm Ngày tự động (YYMMDD_)", systemImage: "calendar")
            }
            
            Button(action: {
                withAnimation { showPrefixBlock = true }
            }) {
                Label("Thêm Tiền tố (Prefix)", systemImage: "text.insert")
            }
            
            Button(action: {
                withAnimation {
                    rule.enableNumbering = true
                    rule.numberingPosition = .prefix
                }
            }) {
                Label("Thêm Đánh số thứ tự (01, 02...)", systemImage: "number")
            }
            
            Button(action: {
                withAnimation { showSuffixBlock = true }
            }) {
                Label("Thêm Hậu tố (Suffix)", systemImage: "text.append")
            }
            
            Button(action: {
                withAnimation { showTrimBlock = true }
            }) {
                Label("Thêm Cắt bớt ký tự (Đầu/Đuôi)", systemImage: "scissors")
            }
            
            Button(action: {
                withAnimation { showFindReplaceBlock = true }
            }) {
                Label("Thêm Tìm & Thay thế chữ", systemImage: "magnifyingglass")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Thêm khối")
                    .font(.system(size: 11, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .opacity(0.6)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [CFinderTheme.FeatureColor.rename.opacity(0.25), Color(hex: "7C3AED").opacity(0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [CFinderTheme.FeatureColor.rename.opacity(0.6), Color(hex: "7C3AED").opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Thêm các khối ghép tên: Ngày, Tiền tố, Đánh số, Hậu tố, Cắt ký tự, Tìm thay thế")
    }
}

struct RecipeQuickUtilitiesBar: View {
    @Binding var rule: RenameRule
    let onReset: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $rule.removeAccents) {
                Text("Bỏ dấu TV")
                    .font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.checkbox)
            
            Divider().frame(height: 14).opacity(0.2)
            
            Menu {
                Button("Giữ khoảng trắng") {
                    rule.replaceSpacesWithDash = false
                    rule.replaceSpacesWithUnderscore = false
                }
                Button("Đổi khoảng trắng thành gạch ngang (-)") {
                    rule.replaceSpacesWithDash = true
                    rule.replaceSpacesWithUnderscore = false
                }
                Button("Đổi khoảng trắng thành gạch dưới (_)") {
                    rule.replaceSpacesWithUnderscore = true
                    rule.replaceSpacesWithDash = false
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Dấu cách:")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Text(spaceLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .opacity(0.5)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Divider().frame(height: 14).opacity(0.2)
            
            Menu {
                ForEach(CaseTransform.allCases, id: \.self) { c in
                    Button(action: { rule.caseTransform = c }) {
                        HStack {
                            Text(c.rawValue)
                            if rule.caseTransform == c { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Kiểu chữ:")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Text(rule.caseTransform.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .opacity(0.5)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Divider().frame(height: 14).opacity(0.2)
            
            Menu {
                ForEach(ExtensionTransform.allCases, id: \.self) { ext in
                    Button(action: { rule.extensionTransform = ext }) {
                        HStack {
                            Text(ext.rawValue)
                            if rule.extensionTransform == ext { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Đuôi tệp:")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Text(rule.extensionTransform.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .opacity(0.5)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            if rule.extensionTransform == .custom {
                HStack(spacing: 2) {
                    Text(".")
                        .font(.system(size: 10.5, design: .monospaced))
                    TextField("mp4...", text: $rule.customExtension)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 55)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            Button(action: onReset) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                    Text("Đặt lại")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Khôi phục toàn bộ quy tắc về mặc định ban đầu")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
    
    private var spaceLabel: String {
        if rule.replaceSpacesWithDash { return "Đổi thành -" }
        if rule.replaceSpacesWithUnderscore { return "Đổi thành _" }
        return "Giữ nguyên"
    }
}


// MARK: - Row Card Component

struct RenameFileRowView: View {
    let item: RenamePreviewItem
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Original file
            HStack(spacing: 8) {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundColor(item.isDirectory ? CFinderTheme.primary : .secondary)
                    .font(.system(size: 14))
                
                Text(item.originalName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Arrow indicator with animated glow on change
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(item.isChanged ? CFinderTheme.primary : Color.secondary.opacity(0.3))
                .scaleEffect(isHovered ? 1.15 : 1.0)
            
            // New name with diff emphasis
            HStack(spacing: 6) {
                Text(item.newName)
                    .font(.system(size: 12, weight: item.isChanged ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(
                        item.hasCollision ? Color.red : (item.isChanged ? CFinderTheme.primary : .secondary)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Status Badge
            statusBadge
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(rowBorderColor, lineWidth: isHovered ? 1.0 : 0.7)
        )
        .scaleEffect(isHovered ? 1.004 : 1.0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
    
    private var rowBackgroundFill: Color {
        if isHovered {
            return item.isChanged ? Color.blue.opacity(0.12) : Color.white.opacity(0.08)
        }
        return item.isChanged ? Color.white.opacity(0.05) : Color.white.opacity(0.02)
    }
    
    private var rowBorderColor: Color {
        if item.hasCollision {
            return Color.red.opacity(isHovered ? 0.6 : 0.4)
        }
        if item.isChanged {
            return Color.blue.opacity(isHovered ? 0.5 : 0.22)
        }
        return Color.white.opacity(isHovered ? 0.15 : 0.05)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if item.hasCollision {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(item.collisionReason ?? "Trùng tên")
            }
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.red.opacity(0.18))
            .foregroundColor(.red)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.red.opacity(0.4), lineWidth: 0.6))
            .shadow(color: Color.red.opacity(0.25), radius: 4, y: 1)
        } else if item.isChanged {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text("Sẽ đổi")
            }
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.18))
            .foregroundColor(CFinderTheme.primary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.blue.opacity(0.4), lineWidth: 0.6))
            .shadow(color: Color.blue.opacity(0.2), radius: 4, y: 1)
        } else {
            Text("Giữ nguyên")
                .font(.system(size: 10.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Footer Bar Component

struct RenameFooterBarView: View {
    let totalCount: Int
    let changedCount: Int
    let collisionCount: Int
    let statusMessage: String?
    let isSuccess: Bool
    let isApplying: Bool
    let onDismiss: () -> Void
    let onApply: () -> Void
    
    @State private var isApplyHovered: Bool = false
    @State private var isCancelHovered: Bool = false
    
    private var canApply: Bool {
        totalCount > 0 && changedCount > 0 && collisionCount == 0 && !isApplying
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Stats pills
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(Color.secondary).frame(width: 6, height: 6)
                    Text("\(totalCount) tệp nạp")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                if changedCount > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(CFinderTheme.FeatureColor.rename).frame(width: 6, height: 6)
                        Text("\(changedCount) sẽ đổi tên")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(CFinderTheme.FeatureColor.rename)
                    }
                }
                
                if collisionCount > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text("\(collisionCount) trùng tên")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: changedCount)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: collisionCount)
            
            Spacer()
            
            if let msg = statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(msg)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(isSuccess ? .green : .red)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            
            Button("Hủy") {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(isCancelHovered ? 0.1 : 0.06))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(isCancelHovered ? 0.22 : 0.12), lineWidth: 0.5))
            .scaleEffect(isCancelHovered ? 1.02 : 1.0)
            .onHover { h in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.78)) {
                    isCancelHovered = h
                }
            }
            
            Button(action: onApply) {
                HStack(spacing: 6) {
                    if isApplying {
                        ProgressView().controlSize(.small)
                    } else if isSuccess {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(changedCount > 0 ? "Áp dụng đổi tên (\(changedCount) tệp)" : "Áp dụng đổi tên")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: canApply
                            ? [CFinderTheme.FeatureColor.rename, Color(hex: "7C3AED")]
                            : [Color.gray.opacity(0.35), Color.gray.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(9)
                .shadow(
                    color: canApply ? CFinderTheme.FeatureColor.rename.opacity(isApplyHovered ? 0.55 : 0.35) : Color.clear,
                    radius: isApplyHovered ? 12 : 7,
                    y: isApplyHovered ? 4 : 2
                )
                .scaleEffect(canApply && isApplyHovered ? 1.025 : 1.0)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(!canApply)
            .keyboardShortcut(.defaultAction)
            .onHover { h in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.78)) {
                    isApplyHovered = h
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            VisualEffectView(material: .headerView, blendingMode: .withinWindow, state: .active)
                .background(Color.black.opacity(0.18))
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1),
            alignment: .top
        )
    }
}

// MARK: - Number Input Field (Direct Edit + Stepper)

struct NumberInputField: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...999999
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 2) {
            TextField("0", text: $text)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 44)
                .onSubmit {
                    commitText()
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        commitText()
                    }
                }
                .onChange(of: text) { _, newText in
                    let digits = newText.filter { $0.isNumber }
                    if digits != newText {
                        text = digits
                    }
                    if let num = Int(digits) {
                        let clamped = min(max(num, range.lowerBound), range.upperBound)
                        if value != clamped {
                            value = clamped
                        }
                    }
                }
                .onChange(of: value) { _, newVal in
                    let currentNum = Int(text.filter { $0.isNumber })
                    if currentNum != newVal {
                        text = "\(newVal)"
                    }
                }
                .onAppear {
                    text = "\(value)"
                }
            
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 2.5)
        .background(Color.white.opacity(0.06))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 0.6))
    }
    
    private func commitText() {
        let digits = text.filter { $0.isNumber }
        if let num = Int(digits) {
            let clamped = min(max(num, range.lowerBound), range.upperBound)
            value = clamped
            text = "\(clamped)"
        } else {
            text = "\(value)"
        }
    }
}

