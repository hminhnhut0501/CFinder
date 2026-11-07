import SwiftUI
import SFinderCore

public struct VideoTwinStudioView: View {
    public let urls: [URL]
    public let onDismiss: () -> Void
    
    @StateObject private var viewModel: VideoTwinStudioViewModel
    @State private var showTrashConfirmAlert = false
    
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
                
                // Main Content (Unified single vertical scroll list)
                if viewModel.isScanning && viewModel.clusters.isEmpty {
                    scanningEmptyState
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
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        viewModel.quickViewURL = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
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
        }
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
            viewModel.startScan()
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
                Text("Bạn có chắc muốn chuyển \(count) video đã chọn vào Thùng rác?\n(Dung lượng giải phóng: \(sizeStr)). Bạn hoàn toàn có thể khôi phục lại từ Thùng rác của Mac nếu cần.")
            }
        )
    }
    
    // MARK: - Header
    
    private var headerSubtitle: String {
        if urls.isEmpty {
            return "Tìm và dọn dẹp video trùng lặp thông minh"
        } else if urls.count == 1 {
            return urls[0].lastPathComponent
        } else if urls.count == 2 {
            return "\(urls[0].lastPathComponent), \(urls[1].lastPathComponent)"
        } else {
            return "\(urls.count) video được phân tích quét trùng lặp"
        }
    }
    
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
                    
                    if viewModel.isScanning {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text(viewModel.activity)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(CFinderTheme.FeatureColor.videoTwin)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(CFinderTheme.FeatureColor.videoTwin.opacity(0.14)))
                    } else {
                        Text("Đã quét xong")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(CFinderTheme.FeatureColor.permissions)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(CFinderTheme.FeatureColor.permissions.opacity(0.14)))
                            .lineLimit(1)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                
                // Targets path (Compact, never overflows header)
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            // Global Selection Strategy Controls
            if !viewModel.clusters.isEmpty {
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
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Tự động giữ lại bản chất lượng cao nhất ở mỗi nhóm và chọn các bản sao để xóa")
                    
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
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Bỏ toàn bộ lựa chọn xóa để bạn tự tay bấm chọn từng video cần xóa")
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
                    .frame(width: 130)
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
            .frame(width: 220)
            .focusEffectDisabled()
            
            // Close Button (Dashboard circular button)
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
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.015))
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
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noDuplicatesEmptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(CFinderTheme.success)
            
            Text("Không phát hiện video trùng lặp!")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CFinderTheme.textPrimary)
            
            Text("Toàn bộ video trong thư mục đã chọn đều là duy nhất và không có bản sao.")
                .font(.system(size: 12))
                .foregroundStyle(CFinderTheme.textMuted)
            
            Button("Đóng cửa sổ") {
                viewModel.cleanup()
                onDismiss()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(CFinderTheme.cardSurfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(CFinderTheme.cardBorder, lineWidth: 1)
            )
            .foregroundStyle(CFinderTheme.textPrimary)
            .padding(.top, 8)
            
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
}
