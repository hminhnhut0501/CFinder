import SwiftUI
import AppKit
import SFinderCore

public struct VideoComparatorView: View {
    public let reports: [VideoDetailedReport]
    public let verdict: ComparisonVerdict?
    public let onKeepOnly: (URL) -> Void
    public let onTrashSingle: (URL) -> Void
    public let onCompareDual: ((URL, URL) -> Void)?
    
    @State private var confirmKeepWinner: URL? = nil
    
    public init(
        reports: [VideoDetailedReport],
        verdict: ComparisonVerdict?,
        onKeepOnly: @escaping (URL) -> Void,
        onTrashSingle: @escaping (URL) -> Void,
        onCompareDual: ((URL, URL) -> Void)? = nil
    ) {
        self.reports = reports
        self.verdict = verdict
        self.onKeepOnly = onKeepOnly
        self.onTrashSingle = onTrashSingle
        self.onCompareDual = onCompareDual
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Winner Recommendation Banner
            if let v = verdict {
                winnerBanner(v)
            }
            
            // Side-by-side Video Comparison Columns
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(reports) { report in
                        let isWinner = report.url == verdict?.winnerURL
                        videoColumnCard(report: report, isWinner: isWinner)
                            .frame(width: 320)
                    }
                }
                .padding(16)
            }
        }
        .alert(
            "Xác nhận giữ video tốt nhất?",
            isPresented: Binding(
                get: { confirmKeepWinner != nil },
                set: { if !$0 { confirmKeepWinner = nil } }
            ),
            actions: {
                Button("Hủy", role: .cancel) {}
                Button("Xác nhận dọn dẹp", role: .destructive) {
                    if let winner = confirmKeepWinner {
                        onKeepOnly(winner)
                    }
                }
            },
            message: {
                Text("Tất cả các video kém hơn trong danh sách so sánh sẽ được chuyển an toàn vào Thùng rác của Mac.")
            }
        )
    }
    
    // MARK: - Winner Banner
    
    private func winnerBanner(_ v: ComparisonVerdict) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundStyle(CFinderTheme.success)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(v.headline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CFinderTheme.textPrimary)
                
                Text(v.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(CFinderTheme.textMuted)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Dual compare button if exactly 2
            if reports.count >= 2, let onCompareDual {
                Button(action: {
                    onCompareDual(reports[0].url, reports[1].url)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.split.2x1.fill")
                            .font(.system(size: 11))
                        Text("So sánh video")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(CFinderTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            
            // Keep Winner & Clean Rest button
            Button(action: {
                confirmKeepWinner = v.winnerURL
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 11))
                    Text("Giữ bản tốt nhất & Dọn dẹp")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(CFinderTheme.success)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: "10B981").opacity(0.12))
        .overlay(
            Rectangle()
                .fill(Color(hex: "10B981").opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Video Column Card
    
    private func videoColumnCard(report: VideoDetailedReport, isWinner: Bool) -> some View {
        let v = report.primaryVideo
        let a = report.primaryAudio
        let score = report.score
        
        return VStack(alignment: .leading, spacing: 10) {
            // Header / Winner Ribbon
            HStack {
                if isWinner {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                        Text("KHUYÊN GIỮ")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(CFinderTheme.success)
                    .clipShape(Capsule())
                } else if score.isBloatedBitrate {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("BƠM BITRATE ẢO")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(CFinderTheme.danger)
                    .clipShape(Capsule())
                }
                
                Spacer()
                
                // Score Pill
                Text("\(Int(score.overallScore)) / 100")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isWinner ? CFinderTheme.success : (score.isBloatedBitrate ? CFinderTheme.danger : CFinderTheme.textPrimary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            
            // File Name & Size
            VStack(alignment: .leading, spacing: 2) {
                Text(report.fileName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CFinderTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: report.fileSize, countStyle: .file))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isWinner ? CFinderTheme.success : Color(hex: "F59E0B"))
                    
                    Text("•")
                        .foregroundStyle(CFinderTheme.textMuted)
                    
                    Text(report.container)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CFinderTheme.primaryLight)
                }
            }
            
            // Video Thumbnail Frame
            Button(action: {
                NSWorkspace.shared.open(report.url)
            }) {
                ZStack {
                    VideoTwinThumbnailView(url: report.url, width: 296, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 32, height: 32)
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .help("Nhấp để phát video")
            
            Divider().background(CFinderTheme.cardBorder)
            
            // Metric Rows
            VStack(spacing: 6) {
                metricRow(title: "Thời lượng", value: formatDuration(report.durationSeconds))
                metricRow(title: "Mật độ Bitrate (BPPF)", value: String(format: "%.3f bppf", score.bitsPerPixelFrame), badge: score.bppfHealth.rawValue, badgeColor: Color(hex: score.bppfHealth.badgeColorHex))
                metricRow(title: "Độ phân giải", value: v.map { "\($0.displayWidth)×\($0.displayHeight)" } ?? "—")
                metricRow(title: "Codec video", value: v?.humanCodec ?? "—")
                metricRow(title: "Bitrate hình", value: v.map { formatBitrate($0.bitrate) } ?? "—")
                metricRow(title: "Khung hình (FPS)", value: v.map { String(format: "%.1f fps", $0.fps) } ?? "—")
                metricRow(title: "Màu & HDR", value: v.map { "\($0.bitDepth)-bit \($0.isHDR ? "HDR" : "SDR")" } ?? "—")
                metricRow(title: "Âm thanh", value: a.map { "\($0.humanCodec) • \($0.channelLayout)" } ?? "—")
            }
            
            // Verdict Note
            Text(score.verdictSummary)
                .font(.system(size: 10))
                .foregroundStyle(CFinderTheme.textMuted)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 6) {
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([report.url])
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text("Finder")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(CFinderTheme.textPrimary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: {
                    onTrashSingle(report.url)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Xóa tệp")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(CFinderTheme.danger.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(CFinderTheme.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(isWinner ? CFinderTheme.success.opacity(0.05) : CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isWinner ? CFinderTheme.success.opacity(0.5) : (score.isBloatedBitrate ? CFinderTheme.danger.opacity(0.4) : CFinderTheme.cardBorder), lineWidth: isWinner ? 1.5 : 1)
        )
    }
    
    private func metricRow(title: String, value: String, badge: String? = nil, badgeColor: Color = .gray) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(CFinderTheme.textMuted)
            
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CFinderTheme.textPrimary)
                    .lineLimit(1)
                
                if let b = badge {
                    Text(b)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(badgeColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    private func formatBitrate(_ bps: Int64) -> String {
        guard bps > 0 else { return "—" }
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000.0)
        } else {
            return "\(bps / 1000) kbps"
        }
    }
    
    private func formatDuration(_ sec: Double) -> String {
        guard sec > 0 else { return "—" }
        let s = Int(sec)
        let m = s / 60
        let h = m / 60
        let remS = s % 60
        let remM = m % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, remM, remS)
        } else {
            return String(format: "%02d:%02d", remM, remS)
        }
    }
}
