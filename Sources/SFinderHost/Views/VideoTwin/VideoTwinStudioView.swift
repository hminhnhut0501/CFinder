import SwiftUI
import UniformTypeIdentifiers
import SFinderCore

public struct VideoTwinStudioView: View {
    public let urls: [URL]
    public let onDismiss: () -> Void
    
    @StateObject private var viewModel: VideoTwinStudioViewModel
    @State private var showTrashConfirmAlert = false
    @State private var isDropTargeted = false
    
    public init(urls: [URL], onDismiss: @escaping () -> Void) {
        self.urls = urls
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: VideoTwinStudioViewModel(urls: urls))
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            // Native Apple Liquid Glass Background
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()
            Color.black.opacity(0.20)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Header Bar
                headerBar
                
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                
                // Secondary Toolbar: Source Folder & Batch Selection Strategy
                if !viewModel.clusters.isEmpty {
                    sourceAndActionToolBar
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 1)
                }
                
                // Main Content (Unified single vertical scroll list)
                if viewModel.isScanning && viewModel.clusters.isEmpty {
                    scanningEmptyState
                } else if !viewModel.hasStartedScanOnce || viewModel.targetURLs.isEmpty {
                    initialSetupDropZoneState
                } else if !viewModel.isScanning && viewModel.clusters.isEmpty {
                    noDuplicatesEmptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(viewModel.filteredClusters.enumerated()), id: \.element.id) { index, cluster in
                                VideoTwinClusterGroupCard(
                                    cluster: cluster,
                                    clusterIndex: index + 1,
                                    assetsByID: viewModel.assetsByID,
                                    selectedForRemoval: viewModel.selectedForRemoval,
                                    isSourceFolderAsset: { viewModel.isAssetInSourceFolder($0) },
                                    onSetAsSourceFolder: { viewModel.setSourceFolder(url: $0) },
                                    onToggleRemoval: { id in
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            viewModel.toggleRemoval(assetID: id)
                                        }
                                    },
                                    onCompare: { a, b, offset in
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            viewModel.activeDualComparison = (a, b, offset)
                                        }
                                    },
                                    onQuickView: { url in
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                            viewModel.quickViewURL = url
                                        }
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                    .animation(.easeInOut(duration: 0.22), value: viewModel.filterTab)
                    .animation(.easeInOut(duration: 0.18), value: viewModel.selectedForRemoval)
                }
                
                Divider()
                    .background(CFinderTheme.cardBorder)
                
                // Bottom Footer Action Bar
                bottomActionBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            // Quick Preview Player Modal
            if let quickURL = viewModel.quickViewURL {
                VideoQuickPreviewModal(url: quickURL) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewModel.quickViewURL = nil
                    }
                }
                .transition(.opacity)
                .zIndex(15)
            }
            
            // Dual player comparison sheet/modal
            if let cmp = viewModel.activeDualComparison {
                VideoTwinDualPlayerModal(
                    assetA: cmp.assetA,
                    assetB: cmp.assetB,
                    offset: cmp.offset,
                    onDismiss: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            viewModel.activeDualComparison = nil
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
                .zIndex(10)
            }
            
            // Status Toast HUD
            if let toast = viewModel.statusToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(CFinderTheme.success)
                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CFinderTheme.textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "1F242C").opacity(0.95))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(CFinderTheme.cardBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                    .padding(.bottom, 60)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation {
                            viewModel.statusToast = nil
                        }
                    }
                }
                .zIndex(20)
            }
            
            // Drag and drop overlay
            if isDropTargeted {
                dropOverlayView
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            if !viewModel.targetURLs.isEmpty && !viewModel.hasStartedScanOnce {
                viewModel.startScan()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .alert(
            "Xác nhận chuyển vào Thùng rác?",
            isPresented: $showTrashConfirmAlert,
            actions: {
                Button("Hủy", role: .cancel) {}
                Button("Chuyển vào Thùng rác", role: .destructive) {
                    Task {
                        await viewModel.trashSelectedFiles()
                    }
                }
            },
            message: {
                let count = viewModel.selectedForRemoval.count
                let sizeStr = ByteCountFormatter.string(fromByteCount: viewModel.selectedRemovalBytes, countStyle: .file)
                let sourceNote = viewModel.sourceFolderName.map { "\n\n🛡️ Folder nguồn '\($0)' được bảo vệ an toàn tuyệt đối (không có bất kỳ tệp nào trong folder này bị xóa)." } ?? ""
                Text("Bạn có chắc muốn chuyển \(count) video đã chọn vào Thùng rác?\n(Dung lượng giải phóng: \(sizeStr)).\(sourceNote)\nBạn hoàn toàn có thể khôi phục lại từ Thùng rác của Mac nếu cần.")
            }
        )
    }
    
    // MARK: - Header
    
    private var headerSubtitle: String {
        if viewModel.targetURLs.isEmpty {
            return "Kéo thả hoặc thêm thư mục/tệp từ máy & ổ cứng ngoài để bắt đầu"
        } else if viewModel.targetURLs.count == 1 {
            let u = viewModel.targetURLs[0]
            let prefix = u.isExternalVolume ? "💽 [Ổ ngoài: \(u.volumeName)] " : "💻 [Ổ máy] "
            return "\(prefix)\(u.lastPathComponent)"
        } else {
            let externalCount = viewModel.targetURLs.filter { $0.isExternalVolume }.count
            let internalCount = viewModel.targetURLs.count - externalCount
            if externalCount > 0 && internalCount > 0 {
                let extName = viewModel.targetURLs.first(where: { $0.isExternalVolume })?.volumeName ?? "Ổ ngoài"
                return "\(viewModel.targetURLs.count) nguồn: 💻 \(internalCount) ổ máy vs 💽 \(externalCount) \(extName)"
            }
            return "\(viewModel.targetURLs.count) nguồn đang được quét so sánh"
        }
    }
    
    // MARK: - Header Bar (Clean, Spacious)
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Squircle Brand Badge (Dashboard style)
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CFinderTheme.FeatureColor.videoTwin.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(CFinderTheme.FeatureColor.videoTwin.opacity(0.28), lineWidth: 1)
                    )
                Image(systemName: "film.stack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CFinderTheme.FeatureColor.videoTwin)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text("VideoTwin Studio")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    if viewModel.isScanning {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text(viewModel.activity)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(CFinderTheme.FeatureColor.videoTwin)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .frame(maxWidth: 180)
                        .background(Capsule().fill(CFinderTheme.FeatureColor.videoTwin.opacity(0.14)))
                    } else if viewModel.hasStartedScanOnce && !viewModel.clusters.isEmpty {
                        Text("Đã quét xong")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(CFinderTheme.FeatureColor.permissions)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(CFinderTheme.FeatureColor.permissions.opacity(0.14)))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Text("Chọn nguồn")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: "06B6D4"))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color(hex: "06B6D4").opacity(0.14)))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                
                // Targets path (Compact, never overflows header)
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            // Add Source & Rescan Buttons
            HStack(spacing: 6) {
                Menu {
                    Button(action: { selectFolderFromInternalDisk() }) {
                        Label("Thêm thư mục từ máy (Mac)...", systemImage: "laptopcomputer")
                    }
                    Button(action: { selectFolderFromExternalDrive() }) {
                        Label("Thêm thư mục từ ổ cứng ngoài / USB...", systemImage: "externaldrive.badge.plus")
                    }
                    Divider()
                    Button(action: { selectIndividualFiles() }) {
                        Label("Thêm tệp video lẻ...", systemImage: "film")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Thêm nguồn")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                
                if viewModel.hasNewSourcesPendingScan || (viewModel.hasStartedScanOnce && !viewModel.isScanning && !viewModel.targetURLs.isEmpty) {
                    Button(action: {
                        withAnimation {
                            viewModel.startScan()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text(viewModel.hasNewSourcesPendingScan ? "Quét lại (Nguồn mới)" : "Quét lại")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(viewModel.hasNewSourcesPendingScan ? CFinderTheme.primary : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Chạy quét lại toàn bộ các nguồn đã thêm")
                }
            }
            
            // Scan Controls
            if viewModel.isScanning {
                Button(action: { viewModel.togglePause() }) {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(viewModel.isPaused ? "Tiếp tục quét" : "Tạm dừng quét")
                
                Button(action: { viewModel.cancelScan() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                        .foregroundColor(CFinderTheme.danger)
                        .padding(6)
                        .background(Circle().fill(CFinderTheme.danger.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Dừng quét")
            }
            
            // Search Input
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                TextField("Tìm kiếm video...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .frame(width: 140)
                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Filter Tabs
            Picker("", selection: $viewModel.filterTab) {
                ForEach(ClusterFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            .focusEffectDisabled()
            
            // Close Button
            Button(action: {
                viewModel.cleanup()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(7)
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
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.015))
    }
    
    // MARK: - Secondary Toolbar (Source Folder & Batch Selection)
    
    private var sourceAndActionToolBar: some View {
        HStack(spacing: 12) {
            // Source Folder Selector Menu
            Menu {
                if !viewModel.detectedFolders.isEmpty {
                    Section("THƯ MỤC TRONG ĐỢT QUÉT") {
                        ForEach(viewModel.detectedFolders, id: \.path) { folder in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    viewModel.setSourceFolder(url: folder.url)
                                }
                            }) {
                                HStack {
                                    if viewModel.sourceFolderPath == folder.path {
                                        Image(systemName: "checkmark")
                                    }
                                    Text("\(folder.name) (\(folder.count) video)")
                                }
                            }
                        }
                    }
                    Divider()
                }
                
                Button(action: {
                    selectCustomSourceFolder()
                }) {
                    Label("Chọn thư mục khác từ máy...", systemImage: "folder.badge.plus")
                }
                
                if viewModel.sourceFolderPath != nil {
                    Divider()
                    Button(role: .destructive, action: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            viewModel.clearSourceFolder()
                        }
                    }) {
                        Label("Bỏ chọn Folder Nguồn", systemImage: "xmark.circle")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.sourceFolderPath != nil ? "shield.fill" : "shield")
                        .font(.system(size: 11))
                        .foregroundColor(viewModel.sourceFolderPath != nil ? Color(hex: "06B6D4") : .white.opacity(0.85))
                    
                    if let name = viewModel.sourceFolderName {
                        Text("Folder nguồn: \(name)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color(hex: "06B6D4"))
                            .lineLimit(1)
                    } else {
                        Text("Chọn Folder nguồn...")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(viewModel.sourceFolderPath != nil ? Color(hex: "06B6D4").opacity(0.14) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(viewModel.sourceFolderPath != nil ? Color(hex: "06B6D4").opacity(0.35) : Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .help(viewModel.sourceFolderPath != nil ? "Folder nguồn: \(viewModel.sourceFolderPath!). Khi tự động chọn, video trong thư mục này luôn được ưu tiên giữ lại." : "Chọn 1 thư mục làm Folder Nguồn để ưu tiên giữ lại các video trong đó")
            
            if viewModel.sourceFolderPath != nil {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.clearSourceFolder()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("Bỏ nguồn")
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Bỏ chọn Folder Nguồn")
                
                Text("• Ưu tiên giữ lại video trong Folder Nguồn khi tự động chọn")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "06B6D4").opacity(0.8))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Global Selection Strategy Controls (Fixed width, never wrap vertically!)
            HStack(spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.autoSelectAllRecommended()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text("Tự động chọn")
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CFinderTheme.primary.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(CFinderTheme.primary.opacity(0.35), lineWidth: 1))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Tự động giữ lại bản trong Folder Nguồn (hoặc bản chất lượng cao nhất) và chọn các bản sao khác để xóa")
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.deselectAll()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                        Text("Tự chọn tay")
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Bỏ toàn bộ lựa chọn xóa để bạn tự tay bấm chọn từng video cần xóa")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.12))
    }
    
    // MARK: - Empty States
    
    private var scanningEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(CFinderTheme.primaryLight)
            
            Text("Đang phân tích các tệp video...")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CFinderTheme.textPrimary)
            
            Text(viewModel.activity)
                .font(.system(size: 12))
                .foregroundStyle(CFinderTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Initial Drop Zone & Setup Screen
    
    private var initialSetupDropZoneState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 28)
                
                // Visual Graphic: Mac vs External Drive Comparison
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [CFinderTheme.primary.opacity(0.22), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                    
                    HStack(spacing: 26) {
                        // Mac Icon Block
                        VStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(hex: "06B6D4").opacity(0.14))
                                    .frame(width: 68, height: 68)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color(hex: "06B6D4").opacity(0.35), lineWidth: 1.5)
                                    )
                                Image(systemName: "laptopcomputer")
                                    .font(.system(size: 30))
                                    .foregroundColor(Color(hex: "06B6D4"))
                            }
                            Text("Ổ đĩa máy")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                        }
                        
                        // Dual Compare Arrow
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(CFinderTheme.primaryLight)
                            Text("So sánh")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(CFinderTheme.primaryLight)
                        }
                        
                        // External Drive Icon Block
                        VStack(spacing: 7) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(hex: "F59E0B").opacity(0.14))
                                    .frame(width: 68, height: 68)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color(hex: "F59E0B").opacity(0.35), lineWidth: 1.5)
                                    )
                                Image(systemName: "externaldrive.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(Color(hex: "F59E0B"))
                            }
                            Text("Ổ cứng rời / USB")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                        }
                    }
                }
                
                VStack(spacing: 8) {
                    Text("Kéo thả thư mục hoặc tệp video vào đây")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Hỗ trợ kéo thả cùng lúc nhiều thư mục từ ổ đĩa máy và ổ cứng ngoài / USB\nđể tìm và so sánh video trùng lặp giữa 2 nơi.")
                        .font(.system(size: 12.5))
                        .foregroundColor(CFinderTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 540)
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: { selectFolderFromInternalDisk() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "laptopcomputer")
                                .font(.system(size: 13))
                            Text("Thêm thư mục từ máy...")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: "06B6D4").opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "06B6D4").opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { selectFolderFromExternalDrive() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "externaldrive.badge.plus")
                                .font(.system(size: 13))
                            Text("Thêm từ ổ cứng ngoài...")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: "F59E0B").opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "F59E0B").opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { selectIndividualFiles() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "film")
                                .font(.system(size: 13))
                            Text("Chọn tệp lẻ...")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                
                // Target Roots List (if any roots added)
                if !viewModel.targetURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("DANH SÁCH NGUỒN QUÉT (\(viewModel.targetURLs.count))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Button("Xóa tất cả") {
                                withAnimation {
                                    viewModel.targetURLs.removeAll()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(CFinderTheme.danger)
                        }
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))], spacing: 8) {
                            ForEach(viewModel.targetRootsInfo) { root in
                                rootChip(root: root)
                            }
                        }
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        // Start Scan Button
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation {
                                    viewModel.startScan()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "film.stack.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Bắt đầu quét so sánh (\(viewModel.targetURLs.count) nguồn)")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [CFinderTheme.primaryLight, CFinderTheme.primary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: CFinderTheme.primary.opacity(0.4), radius: 8, y: 4)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .frame(maxWidth: 680)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                
                Spacer(minLength: 28)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func rootChip(root: VideoTwinStudioViewModel.TargetRootInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: root.isExternal ? "externaldrive.fill" : (root.isDirectory ? "folder.fill" : "film"))
                .font(.system(size: 13))
                .foregroundColor(root.isExternal ? Color(hex: "F59E0B") : Color(hex: "06B6D4"))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(root.isExternal ? "[Ổ ngoài: \(root.volumeName)]" : "[Ổ máy]")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(root.isExternal ? Color(hex: "F59E0B") : Color(hex: "06B6D4"))
                    Text(root.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(root.path)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    viewModel.removeTargetURL(root.url)
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(5)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("Bỏ nguồn này")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(root.isExternal ? Color(hex: "F59E0B").opacity(0.10) : Color(hex: "06B6D4").opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(root.isExternal ? Color(hex: "F59E0B").opacity(0.3) : Color(hex: "06B6D4").opacity(0.3), lineWidth: 1)
        )
    }
    
    private var noDuplicatesEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(CFinderTheme.success)
            
            Text("Không phát hiện video trùng lặp!")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CFinderTheme.textPrimary)
            
            Text("Toàn bộ video trong các nguồn đã quét đều là duy nhất và không có bản sao.")
                .font(.system(size: 12))
                .foregroundStyle(CFinderTheme.textMuted)
            
            HStack(spacing: 10) {
                Button(action: { selectFolderFromExternalDrive() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "externaldrive.badge.plus")
                        Text("Thêm từ ổ cứng ngoài...")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "F59E0B").opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "F59E0B").opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                Button(action: { selectFolderFromInternalDisk() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "laptopcomputer")
                        Text("Thêm từ ổ đĩa máy...")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "06B6D4").opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "06B6D4").opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                Button("Đóng cửa sổ") {
                    viewModel.cleanup()
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .foregroundStyle(CFinderTheme.textPrimary)
            }
            .padding(.top, 6)
            
            Text("💡 Bạn có thể kéo thả trực tiếp thư mục hoặc tệp video vào đây bất cứ lúc nào.")
                .font(.system(size: 11))
                .foregroundColor(Color.white.opacity(0.45))
                .padding(.top, 4)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Bottom Footer Bar
    
    private var bottomActionBar: some View {
        HStack {
            // Stats with clear icons, zero redundant text
            HStack(spacing: 14) {
                statItem(
                    icon: "film.stack",
                    value: "\(viewModel.clusters.count) nhóm"
                )
                statItem(
                    icon: "trash",
                    value: "\(viewModel.selectedForRemoval.count) video chọn xóa",
                    valueColor: viewModel.selectedForRemoval.isEmpty ? CFinderTheme.textMuted : CFinderTheme.danger
                )
                statItem(
                    icon: "arrow.down.circle.fill",
                    value: "\(ByteCountFormatter.string(fromByteCount: viewModel.selectedRemovalBytes, countStyle: .file)) giải phóng",
                    valueColor: Color(hex: "F59E0B")
                )
                
                if let src = viewModel.sourceFolderName {
                    statItem(
                        icon: "lock.shield.fill",
                        value: "Nguồn: \(src)",
                        valueColor: Color(hex: "06B6D4")
                    )
                }
            }
            
            Spacer()
            
            // Clean action buttons
            Button("Đóng") {
                viewModel.cleanup()
                onDismiss()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(CFinderTheme.textPrimary)
            
            let count = viewModel.selectedForRemoval.count
            let sizeStr = ByteCountFormatter.string(fromByteCount: viewModel.selectedRemovalBytes, countStyle: .file)
            Button(action: {
                showTrashConfirmAlert = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11))
                    Text(count > 0 ? "Dọn dẹp \(count) video (\(sizeStr))" : "Dọn dẹp")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(viewModel.selectedForRemoval.isEmpty ? Color.gray.opacity(0.25) : CFinderTheme.danger)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedForRemoval.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            VisualEffectView(material: .headerView, blendingMode: .withinWindow, state: .active)
                .background(Color.black.opacity(0.18))
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
    }
    
    private func statItem(icon: String, value: String, valueColor: Color = CFinderTheme.textPrimary) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(CFinderTheme.textMuted)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(valueColor)
        }
    }
    
    private func selectCustomSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Chọn làm Folder Nguồn"
        panel.message = "Chọn thư mục nguồn cần bảo vệ (không bao giờ bị chọn xóa các tệp trùng lặp):"
        if panel.runModal() == .OK, let url = panel.url {
            withAnimation(.easeInOut(duration: 0.22)) {
                viewModel.setSourceFolder(url: url)
            }
        }
    }
    
    // MARK: - Source Selectors (Internal Mac vs External Volumes)
    
    private func selectFolderFromInternalDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        panel.prompt = "Thêm nguồn"
        panel.message = "Chọn một hoặc nhiều thư mục / tệp video trên ổ đĩa máy (Mac):"
        if panel.runModal() == .OK {
            viewModel.addTargetURLs(panel.urls)
        }
    }
    
    private func selectFolderFromExternalDrive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.prompt = "Thêm nguồn"
        panel.message = "Chọn một hoặc nhiều thư mục / tệp video trên ổ cứng ngoài, thẻ nhớ hoặc USB:"
        if panel.runModal() == .OK {
            viewModel.addTargetURLs(panel.urls)
        }
    }
    
    private func selectIndividualFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Thêm tệp"
        panel.message = "Chọn một hoặc nhiều tệp video:"
        if panel.runModal() == .OK {
            viewModel.addTargetURLs(panel.urls)
        }
    }
    
    // MARK: - Drag and Drop Handling
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var droppedURLs: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        droppedURLs.append(url)
                    }
                    group.leave()
                }
            } else {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        droppedURLs.append(url)
                    } else if let url = item as? URL {
                        droppedURLs.append(url)
                    }
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            if !droppedURLs.isEmpty {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    viewModel.addTargetURLs(droppedURLs)
                }
            }
        }
        return true
    }
    
    // MARK: - Drag Overlay View
    
    private var dropOverlayView: some View {
        ZStack {
            Color.black.opacity(0.68)
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CFinderTheme.primary.opacity(0.2))
                        .frame(width: 80, height: 80)
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(CFinderTheme.primaryLight)
                }
                Text("Thả thư mục hoặc tệp video vào đây")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text("Hỗ trợ kéo thả cùng lúc từ ổ đĩa máy và ổ cứng ngoài / USB")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(32)
            .background(
                VisualEffectView(material: .popover, blendingMode: .withinWindow, state: .active)
                    .background(Color(hex: "1F242C").opacity(0.94))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CFinderTheme.primaryLight, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .shadow(color: .black.opacity(0.5), radius: 24)
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .zIndex(100)
    }
}
