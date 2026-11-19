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
        let pixA = (streamA?.displayWidth ?? 0) * (streamA?.displayHeight ?? 0)
        let pixB = (streamB?.displayWidth ?? 0) * (streamB?.displayHeight ?? 0)
        
        let bA = effectiveBitrate(asset: assetA, stream: streamA)
        let bB = effectiveBitrate(asset: assetB, stream: streamB)
        
        let fpsA = streamA?.nominalFPS ?? 0
        let fpsB = streamB?.nominalFPS ?? 0
        
        let rankA = codecRank(streamA)
        let rankB = codecRank(streamB)
        
        let sizeA = assetA.fileIdentity.fileSize
        let sizeB = assetB.fileIdentity.fileSize
        
        let durA = assetA.metadata?.durationSeconds ?? 0
        let durB = assetB.metadata?.durationSeconds ?? 0
        
        return VStack(spacing: 8) {
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
                    valB: streamB.map { "\($0.displayWidth)×\($0.displayHeight)" } ?? "—",
                    isBestA: pixA > pixB && pixB > 0,
                    isBestB: pixB > pixA && pixA > 0
                )
                metricRow(
                    title: "Bitrate",
                    valA: formatBitrate(bA),
                    valB: formatBitrate(bB),
                    isBestA: bA > bB && bB > 0,
                    isBestB: bB > bA && bA > 0
                )
                metricRow(
                    title: "Định dạng Codec",
                    valA: formatCodec(streamA),
                    valB: formatCodec(streamB),
                    isBestA: rankA > rankB,
                    isBestB: rankB > rankA
                )
                metricRow(
                    title: "Tốc độ khung hình (FPS)",
                    valA: streamA.map { String(format: "%.1f fps", $0.nominalFPS) } ?? "—",
                    valB: streamB.map { String(format: "%.1f fps", $0.nominalFPS) } ?? "—",
                    isBestA: fpsA > fpsB + 0.5,
                    isBestB: fpsB > fpsA + 0.5
                )
                metricRow(
                    title: "Dung lượng tệp",
                    valA: ByteCountFormatter.string(fromByteCount: sizeA, countStyle: .file),
                    valB: ByteCountFormatter.string(fromByteCount: sizeB, countStyle: .file),
                    isBestA: sizeA < sizeB && pixA >= pixB && sizeA > 0,
                    isBestB: sizeB < sizeA && pixB >= pixA && sizeB > 0
                )
                metricRow(
                    title: "Thời lượng",
                    valA: formatDuration(durA),
                    valB: formatDuration(durB),
                    isBestA: durA > durB + 1.0,
                    isBestB: durB > durA + 1.0
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
    
    private func metricRow(title: String, valA: String, valB: String, isBestA: Bool, isBestB: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CFinderTheme.textMuted)
                .frame(width: 130, alignment: .leading)
            
            Text(valA)
                .font(.system(size: 11, weight: isBestA ? .bold : .regular))
                .foregroundStyle(isBestA ? CFinderTheme.success : CFinderTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(valB)
                .font(.system(size: 11, weight: isBestB ? .bold : .regular))
                .foregroundStyle(isBestB ? CFinderTheme.success : CFinderTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
    
    private func effectiveBitrate(asset: VideoAsset, stream: VideoStreamMetadata?) -> Int64 {
        if let b = stream?.bitrate, b > 0 { return b }
        let dur = asset.metadata?.durationSeconds ?? 0
        if dur > 0, asset.fileIdentity.fileSize > 0 {
            return Int64(Double(asset.fileIdentity.fileSize * 8) / dur)
        }
        return 0
    }
    
    private func codecRank(_ s: VideoStreamMetadata?) -> Int {
        guard let s else { return 0 }
        let raw = s.codec.lowercased()
        var rank = 1
        if raw.contains("av01") || raw.contains("av1") { rank = 4 }
        else if raw.contains("hvc") || raw.contains("hevc") || raw.contains("h265") { rank = 3 }
        else if raw.contains("avc") || raw.contains("h264") { rank = 2 }
        if s.isHDR || (s.bitDepth ?? 8) > 8 { rank += 1 }
        return rank
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
