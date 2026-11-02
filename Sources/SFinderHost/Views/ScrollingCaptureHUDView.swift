import SwiftUI
import AppKit
import SFinderCore

public struct ScrollingCaptureHUDView: View {
    @ObservedObject private var engine = ScrollingCaptureEngine.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar
            modeSelector
            statsAndPreview
            actionButtons
        }
        .padding(16)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "121214").opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 25, y: 12)
        )
    }
    
    // MARK: - Subcomponents
    
    private var headerBar: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                
                Image(systemName: "arrow.up.and.down.and.sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Chụp ảnh cuộn")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.white)
                
                Text(statusText)
                    .font(.system(size: 10.5))
                    .foregroundColor(statusColor)
            }
            
            Spacer()
            
            Button(action: {
                engine.cancelSession()
                ScrollingCaptureHUDController.shared.hideHUD()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }
    
    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(ScrollingCaptureMode.allCases) { mode in
                let isSelected = engine.currentMode == mode
                Button(action: {
                    guard case .ready = engine.state else { return }
                    engine.currentMode = mode
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
    
    private var statsAndPreview: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnailBox
            metricsBox
        }
        .frame(height: 110)
    }
    
    private var thumbnailBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.4))
                .frame(width: 72, height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            
            if let thumb = engine.currentPreviewThumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 68, maxHeight: 106)
                    .cornerRadius(6)
            } else {
                VStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("Đang chờ...")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
    }
    
    private var metricsBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("KÍCH THƯỚC ẢNH DÀI")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Text(engine.stats.formattedDimensions)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("SỐ LÁT GHÉP")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.35))
                Text("\(engine.stats.frameCount) khung hình")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch engine.state {
            case .ready:
                Button(action: {
                    engine.startCapturing()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text(engine.currentMode == .autoScroll ? "Bắt đầu tự cuộn" : "Bắt đầu ghi cuộn tay")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: "10B981"))
                    )
                }
                .buttonStyle(.plain)
                
            case .capturing(let mode):
                if mode == .autoScroll {
                    Button(action: {
                        engine.toggleAutoScrollPause()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: engine.isAutoScrollPaused ? "play.fill" : "pause.fill")
                            Text(engine.isAutoScrollPaused ? "Tiếp tục" : "Tạm dừng")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: {
                    engine.finishCapture()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                        Text("Hoàn tất (Xong)")
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
                }
                .buttonStyle(.plain)
                
            case .stitching:
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Đang hoàn thiện ảnh...")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                
            default:
                EmptyView()
            }
        }
    }
    
    private var statusText: String {
        switch engine.state {
        case .ready: return "Sẵn sàng chụp"
        case .capturing(let mode):
            return mode == .autoScroll ? (engine.isAutoScrollPaused ? "Đang tạm dừng" : "Đang tự động cuộn...") : "Đang cuộn tay..."
        case .stitching: return "Đang ghép nối..."
        case .completed: return "Đã hoàn thành!"
        default: return ""
        }
    }
    
    private var statusColor: Color {
        switch engine.state {
        case .ready: return .white.opacity(0.6)
        case .capturing: return Color(hex: "10B981")
        case .stitching: return .orange
        case .completed: return .cyan
        default: return .white.opacity(0.5)
        }
    }
}
