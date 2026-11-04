import SwiftUI
import AppKit
import SFinderCore

public struct VideoInspectorMasterView: View {
    public let urls: [URL]
    public let onDismiss: () -> Void
    
    @StateObject private var viewModel: VideoInspectorViewModel
    
    public init(urls: [URL], onDismiss: @escaping () -> Void) {
        self.urls = urls
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: VideoInspectorViewModel(urls: urls))
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()
            Color.black.opacity(0.20)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Window Header
                headerBar
                
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                
                // Content
                Group {
                    if viewModel.isLoading {
                        loadingView
                            .transition(.opacity)
                    } else if let err = viewModel.errorMessage {
                        errorView(err)
                            .transition(.opacity)
                    } else if viewModel.reports.isEmpty {
                        emptyView
                            .transition(.opacity)
                    } else {
                        mainContentView
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            
            // Dual video player comparison modal
            if let cmp = viewModel.activeDualComparison {
                VideoInspectorDualPlayerModal(
                    urlA: cmp.0,
                    urlB: cmp.1,
                    onDismiss: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
            
            // Toast HUD
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
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation { viewModel.statusToast = nil }
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 580)
        .onAppear {
            viewModel.loadReports()
        }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // Squircle Brand Badge (Dashboard style)
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CFinderTheme.FeatureColor.videoInspector.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(CFinderTheme.FeatureColor.videoInspector.opacity(0.28), lineWidth: 1)
                    )
                Image(systemName: viewModel.reports.count >= 2 ? "rectangle.split.2x1.fill" : "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(CFinderTheme.FeatureColor.videoInspector)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.reports.count >= 2 ? "So sánh & Chấm điểm Video" : "Chi tiết thông số Video")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(urls.count > 1 ? "\(urls.count) video được phân tích đối chiếu" : urls.first?.lastPathComponent ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Multi-tab selector if >= 2 videos (Compact, non-overlapping labels)
            if viewModel.reports.count >= 2 {
                Picker("", selection: $viewModel.selectedTab) {
                    Text("So sánh").tag(0)
                    ForEach(Array(viewModel.reports.enumerated()), id: \.offset) { idx, rep in
                        Text("Video \(idx + 1)").tag(idx + 1)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: CGFloat(viewModel.reports.count + 1) * 75)
                .focusEffectDisabled()
            }
            
            // Close Button
            Button(action: onDismiss) {
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
    
    // MARK: - Main Content Switcher
    
    private var mainContentView: some View {
        Group {
            if viewModel.reports.count == 1 {
                VideoInspectorSingleView(report: viewModel.reports[0])
            } else {
                if viewModel.selectedTab == 0 {
                    VideoComparatorView(
                        reports: viewModel.reports,
                        verdict: viewModel.comparisonVerdict,
                        onKeepOnly: { winner in
                            Task { await viewModel.keepOnly(winnerURL: winner) }
                        },
                        onTrashSingle: { url in
                            Task { await viewModel.trashSingle(url: url) }
                        },
                        onCompareDual: { a, b in
                            viewModel.activeDualComparison = (a, b)
                        }
                    )
                } else if viewModel.selectedTab - 1 < viewModel.reports.count {
                    VideoInspectorSingleView(report: viewModel.reports[viewModel.selectedTab - 1])
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: viewModel.selectedTab)
    }
    
    // MARK: - States
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Đang trích xuất & chấm điểm thông số video...")
                .font(.system(size: 12))
                .foregroundStyle(CFinderTheme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ err: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(CFinderTheme.danger)
            Text(err)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CFinderTheme.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "film")
                .font(.system(size: 32))
                .foregroundStyle(CFinderTheme.textMuted.opacity(0.5))
            Text("Không còn video nào để xem")
                .font(.system(size: 13))
                .foregroundStyle(CFinderTheme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
