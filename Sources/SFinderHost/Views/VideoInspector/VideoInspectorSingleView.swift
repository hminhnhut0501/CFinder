import SwiftUI
import AppKit
import SFinderCore

public struct VideoInspectorSingleView: View {
    public let report: VideoDetailedReport
    
    public init(report: VideoDetailedReport) {
        self.report = report
    }
    
    private var primaryVideo: VideoStreamDetail? {
        report.primaryVideo
    }
    
    private var primaryAudio: AudioStreamDetail? {
        report.primaryAudio
    }
    
    private var scoreColor: Color {
        let s = report.score.overallScore
        if s >= 75 { return CFinderTheme.success }
        if s >= 50 { return Color(hex: "F59E0B") }
        return CFinderTheme.danger
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Hero Header Card
                heroHeaderCard
                
                // BPPF Bitrate Quality & Bloat Gauge
                bppfGaugeCard
                
                // Video Stream Details
                videoStreamCard
                
                // Audio Stream Details
                if let audio = primaryAudio {
                    audioStreamCard(audio: audio)
                }
                
                // Intelligent AI Score & Adjustments
                scoreBreakdownCard
            }
            .padding(16)
        }
    }
    
    // MARK: - Hero Header
    
    private var heroHeaderCard: some View {
        HStack(spacing: 14) {
            // Video Thumbnail Preview
            Button(action: {
                NSWorkspace.shared.open(report.url)
            }) {
                ZStack {
                    VideoTwinThumbnailView(url: report.url, width: 88, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 24, height: 24)
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .help("Nhấp để phát video")
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(report.fileName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CFinderTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text(report.container)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CFinderTheme.primaryLight)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CFinderTheme.primary.opacity(0.15))
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 10))
                        Text(ByteCountFormatter.string(fromByteCount: report.fileSize, countStyle: .file))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(CFinderTheme.textMuted)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(formatDuration(report.durationSeconds))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(CFinderTheme.textMuted)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 10))
                        Text(formatBitrate(report.totalBitrate))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(CFinderTheme.textMuted)
                }
            }
            
            Spacer()
            
            // Overall Quality Score Ring / Badge
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .stroke(scoreColor.opacity(0.2), lineWidth: 4)
                        .frame(width: 46, height: 46)
                    Circle()
                        .trim(from: 0, to: CGFloat(report.score.overallScore / 100.0))
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 46, height: 46)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(Int(report.score.overallScore))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(scoreColor)
                }
                
                Text("Điểm VQS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CFinderTheme.textMuted)
            }
        }
        .padding(14)
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CFinderTheme.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - BPPF Gauge Card
    
    private var bppfGaugeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: report.score.bppfHealth.badgeColorHex))
                    Text("Mật độ Dữ liệu Bitrate / Điểm ảnh (BPPF)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CFinderTheme.textPrimary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text(String(format: "%.3f", report.score.bitsPerPixelFrame))
                        .font(.system(size: 11, weight: .bold))
                    Text("bppf")
                        .font(.system(size: 9))
                }
                .foregroundStyle(CFinderTheme.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                
                Text(report.score.bppfHealth.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: report.score.bppfHealth.badgeColorHex))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color(hex: report.score.bppfHealth.badgeColorHex).opacity(0.15))
                    .clipShape(Capsule())
            }
            
            if report.score.isBloatedBitrate {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CFinderTheme.danger)
                    Text("Cảnh báo: Video có bitrate quá cao bất thường so với độ phân giải. Điều này gây lãng phí dung lượng lưu trữ mà mắt người không thể nhận thấy thêm chi tiết.")
                        .font(.system(size: 11))
                        .foregroundStyle(CFinderTheme.danger)
                }
                .padding(8)
                .background(CFinderTheme.danger.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(report.score.isBloatedBitrate ? CFinderTheme.danger.opacity(0.4) : CFinderTheme.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Video Stream Card
    
    private var videoStreamCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "video.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(CFinderTheme.primaryLight)
                Text("Thông số Luồng Video (Video Stream)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CFinderTheme.textPrimary)
            }
            
            if let v = primaryVideo {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    specTile(label: "Codec / Chuẩn nén", value: "\(v.humanCodec) (\(v.codec))")
                    specTile(label: "Độ phân giải & Tỉ lệ", value: "\(v.displayWidth)×\(v.displayHeight) (\(v.aspectRatio))")
                    specTile(label: "Bitrate luồng hình", value: formatBitrate(v.bitrate))
                    specTile(label: "Tốc độ khung hình", value: String(format: "%.2f fps (%@)", v.fps, v.isVFR ? "VFR Biến thiên" : "CFR Cố định"))
                    specTile(label: "Độ sâu màu & Dải động", value: "\(v.bitDepth)-bit \(v.isHDR ? "HDR" : "SDR")")
                    specTile(label: "Chroma Subsampling", value: v.chromaSubsampling)
                    if let prim = v.colorPrimaries {
                        specTile(label: "Không gian màu (Primaries)", value: prim)
                    }
                    if let tf = v.transferCharacteristics {
                        specTile(label: "Hàm truyền dải động (Transfer)", value: tf)
                    }
                }
            } else {
                Text("Không tìm thấy luồng hình ảnh.")
                    .font(.system(size: 11))
                    .foregroundStyle(CFinderTheme.textMuted)
            }
        }
        .padding(12)
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CFinderTheme.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Audio Stream Card
    
    private func audioStreamCard(audio: AudioStreamDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "F59E0B"))
                Text("Thông số Luồng Âm thanh (Audio Stream)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CFinderTheme.textPrimary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                specTile(label: "Định dạng âm thanh", value: "\(audio.humanCodec) (\(audio.codec))")
                specTile(label: "Cấu hình kênh (Layout)", value: "\(audio.channelLayout) (\(audio.channels) kênh)")
                specTile(label: "Tần số lấy mẫu", value: String(format: "%.1f kHz", audio.sampleRate / 1000.0))
                specTile(label: "Bitrate âm thanh", value: audio.bitrate.map { formatBitrate($0) } ?? "Biến thiên (VBR)")
            }
        }
        .padding(12)
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CFinderTheme.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Score Breakdown Card
    
    private var scoreBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(CFinderTheme.textAccent)
                Text("Đánh giá Trí tuệ Nhân tạo & Chi tiết Điểm số")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CFinderTheme.textPrimary)
            }
            
            Text(report.score.verdictSummary)
                .font(.system(size: 12))
                .foregroundStyle(CFinderTheme.textPrimary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            if !report.score.adjustments.isEmpty {
                VStack(spacing: 5) {
                    ForEach(report.score.adjustments) { adj in
                        HStack {
                            Text(adj.aspect)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(adj.points >= 0 ? CFinderTheme.success : CFinderTheme.danger)
                                .frame(width: 90, alignment: .leading)
                            
                            Text(adj.description)
                                .font(.system(size: 11))
                                .foregroundStyle(CFinderTheme.textMuted)
                            
                            Spacer()
                            
                            Text(adj.points >= 0 ? "+\(Int(adj.points))" : "\(Int(adj.points))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(adj.points >= 0 ? CFinderTheme.success : CFinderTheme.danger)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background((adj.points >= 0 ? CFinderTheme.success : CFinderTheme.danger).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CFinderTheme.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Subcomponents & Helpers
    
    private func specTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(CFinderTheme.textMuted)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CFinderTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    private func formatBitrate(_ bps: Int64) -> String {
        guard bps > 0 else { return "—" }
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000.0)
        } else {
            return "\(bps / 1000) kbps"
        }
    }
    
    private func formatDuration(_ s: Double) -> String {
        guard s > 0 else { return "00:00" }
        let total = Int(s)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
