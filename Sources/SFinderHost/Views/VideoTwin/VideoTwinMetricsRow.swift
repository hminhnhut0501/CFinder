import SwiftUI
import SFinderCore

public struct VideoTwinMetricsRow: View {
    public let assetA: VideoAsset
    public let assetB: VideoAsset
    
    private var streamA: VideoStreamMetadata? { assetA.metadata?.videoStream }
    private var streamB: VideoStreamMetadata? { assetB.metadata?.videoStream }
    
    public init(assetA: VideoAsset, assetB: VideoAsset) {
        self.assetA = assetA
        self.assetB = assetB
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("THÔNG SỐ KỸ THUẬT SO SÁNH")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CFinderTheme.textAccent)
                Spacer()
            }
            .padding(.bottom, 2)
            
            // Grid of comparison
            VStack(spacing: 6) {
                metricRow(
                    title: "Độ phân giải",
                    valA: streamA.map { "\($0.displayWidth)×\($0.displayHeight)" } ?? "—",
                    valB: streamB.map { "\($0.displayWidth)×\($0.displayHeight)" } ?? "—"
                )
                metricRow(
                    title: "Bitrate",
                    valA: formatBitrate(streamA?.bitrate),
                    valB: formatBitrate(streamB?.bitrate)
                )
                metricRow(
                    title: "Định dạng Codec",
                    valA: formatCodec(streamA),
                    valB: formatCodec(streamB)
                )
                metricRow(
                    title: "Tốc độ khung hình (FPS)",
                    valA: streamA.map { String(format: "%.1f fps", $0.nominalFPS) } ?? "—",
                    valB: streamB.map { String(format: "%.1f fps", $0.nominalFPS) } ?? "—"
                )
                metricRow(
                    title: "Dung lượng tệp",
                    valA: ByteCountFormatter.string(fromByteCount: assetA.fileIdentity.fileSize, countStyle: .file),
                    valB: ByteCountFormatter.string(fromByteCount: assetB.fileIdentity.fileSize, countStyle: .file)
                )
                metricRow(
                    title: "Thời lượng",
                    valA: formatDuration(assetA.metadata?.durationSeconds),
                    valB: formatDuration(assetB.metadata?.durationSeconds)
                )
            }
        }
        .padding(12)
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CFinderTheme.cardBorder, lineWidth: 1)
        )
    }
    
    private func metricRow(title: String, valA: String, valB: String) -> some View {
        let isDiff = valA != valB && valA != "—" && valB != "—"
        return HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CFinderTheme.textMuted)
                .frame(width: 130, alignment: .leading)
            
            Text(valA)
                .font(.system(size: 11, weight: isDiff ? .semibold : .regular))
                .foregroundStyle(isDiff ? CFinderTheme.primaryLight : CFinderTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(valB)
                .font(.system(size: 11, weight: isDiff ? .semibold : .regular))
                .foregroundStyle(isDiff ? Color(hex: "F472B6") : CFinderTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
    
    private func formatBitrate(_ bitrate: Int64?) -> String {
        guard let b = bitrate, b > 0 else { return "—" }
        return String(format: "%.2f Mbps", Double(b) / 1_000_000.0)
    }
    
    private func formatCodec(_ s: VideoStreamMetadata?) -> String {
        guard let s else { return "—" }
        let raw = s.codec.lowercased()
        let name = (raw.contains("hvc") || raw.contains("hevc") || raw.contains("h265")) ? "HEVC / H.265" :
                   (raw.contains("avc") || raw.contains("h264")) ? "AVC / H.264" : s.codec.uppercased()
        return name + (s.isHDR ? " (HDR)" : "")
    }
    
    private func formatDuration(_ sec: Double?) -> String {
        guard let s = sec, s.isFinite, s >= 0 else { return "—" }
        let total = Int(s)
        let m = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", m, remainder)
    }
}
