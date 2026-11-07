import SwiftUI
import AppKit
import AVKit
import SFinderCore

// MARK: - Cluster Parameter Diff Model

private struct ClusterParamDiff {
    let sizeDiffers: Bool
    let minSize: Int64
    let maxSize: Int64
    
    let resolutionDiffers: Bool
    let maxPixels: Int
    
    let bitrateDiffers: Bool
    let maxBitrate: Int64
    
    let codecDiffers: Bool
    
    init(members: [ClusterMember], assetsByID: [UUID: VideoAsset]) {
        let assets = members.compactMap { assetsByID[$0.assetID] }
        
        let sizes = assets.map { $0.fileIdentity.fileSize }
        sizeDiffers = Set(sizes).count > 1
        minSize = sizes.min() ?? 0
        maxSize = sizes.max() ?? 0
        
        let pixels = assets.map { a -> Int in
            let w = a.metadata?.videoStream?.displayWidth ?? 0
            let h = a.metadata?.videoStream?.displayHeight ?? 0
            return w * h
        }
        resolutionDiffers = Set(pixels).count > 1
        maxPixels = pixels.max() ?? 0
        
        let bitrates = assets.map { $0.metadata?.videoStream?.bitrate ?? 0 }
        bitrateDiffers = Set(bitrates).count > 1
        maxBitrate = bitrates.max() ?? 0
        
        let codecs = assets.map { $0.metadata?.videoStream?.codec.lowercased() ?? "" }
        codecDiffers = Set(codecs).count > 1
    }
}

// MARK: - Cluster Group Card (Clean, Minimalist Layout)

public struct VideoTwinClusterGroupCard: View {
    public let cluster: DuplicateCluster
    public let clusterIndex: Int
    public let assetsByID: [UUID: VideoAsset]
    public let selectedForRemoval: Set<UUID>
    public let onToggleRemoval: (UUID) -> Void
    public let onCompare: (VideoAsset, VideoAsset, Double) -> Void
    public let onQuickView: (URL) -> Void
    
    private var isExact: Bool {
        cluster.representativeMatchType == .exact
    }
    
    private var bestMemberID: UUID? {
        cluster.recommendedKeepID ?? cluster.members.first?.assetID
    }
    
    private var diff: ClusterParamDiff {
        ClusterParamDiff(members: cluster.members, assetsByID: assetsByID)
    }
    
    private var reclaimableStr: String {
        ByteCountFormatter.string(fromByteCount: cluster.reclaimableBytes, countStyle: .file)
    }
    
    public init(
        cluster: DuplicateCluster,
        clusterIndex: Int,
        assetsByID: [UUID: VideoAsset],
        selectedForRemoval: Set<UUID>,
        onToggleRemoval: @escaping (UUID) -> Void,
        onCompare: @escaping (VideoAsset, VideoAsset, Double) -> Void,
        onQuickView: @escaping (URL) -> Void
    ) {
        self.cluster = cluster
        self.clusterIndex = clusterIndex
        self.assetsByID = assetsByID
        self.selectedForRemoval = selectedForRemoval
        self.onToggleRemoval = onToggleRemoval
        self.onCompare = onCompare
        self.onQuickView = onQuickView
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Clean Cluster Header
            clusterHeaderBar
            
            Divider().background(Color.white.opacity(0.06))
            
            // Member Video Rows with subtle dividers
            VStack(spacing: 0) {
                ForEach(Array(cluster.members.enumerated()), id: \.element.id) { index, member in
                    if let asset = assetsByID[member.assetID] {
                        let isBest = member.assetID == bestMemberID
                        let isMarkedForTrash = selectedForRemoval.contains(member.assetID)
                        
                        videoRow(asset: asset, isBest: isBest, isMarkedForTrash: isMarkedForTrash)
                        
                        if index < cluster.members.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.04))
                                .padding(.leading, 88)
                        }
                    }
                }
            }
        }
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(CFinderTheme.cardBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Cluster Header Bar
    
    private var clusterHeaderBar: some View {
        HStack(spacing: 8) {
            // Index & Type Badge
            Text("#\(clusterIndex)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CFinderTheme.textMuted)
            
            Image(systemName: isExact ? "checkmark.seal.fill" : "sparkles.tv")
                .font(.system(size: 11))
                .foregroundStyle(isExact ? CFinderTheme.success : CFinderTheme.primaryLight)
            
            Text(isExact ? "Trùng 100%" : "Trùng nội dung")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CFinderTheme.textPrimary)
            
            if !isExact {
                Text(String(format: "%.0f%% tương đồng", cluster.overallSimilarity * 100))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CFinderTheme.textAccent)
            }
            
            Text("•")
                .foregroundStyle(CFinderTheme.textMuted.opacity(0.4))
            
            Text("Tiết kiệm: \(reclaimableStr)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "F59E0B"))
            
            Spacer()
            
            // Compare side by side if >= 2 videos
            if cluster.members.count >= 2 {
                let memberA = cluster.members[0]
                let memberB = cluster.members[1]
                if let assetA = assetsByID[memberA.assetID], let assetB = assetsByID[memberB.assetID] {
                    Button(action: {
                        onCompare(assetA, assetB, 0.0)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.split.2x1.fill")
                                .font(.system(size: 9))
                            Text("So sánh")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(CFinderTheme.primaryLight)
                    }
                    .buttonStyle(.plain)
                    .help("Mở trình so sánh đồng bộ hai video đối chiếu từng khung hình")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02))
    }
    
    // MARK: - Clean Video Row
    
    private func videoRow(asset: VideoAsset, isBest: Bool, isMarkedForTrash: Bool) -> some View {
        let stream = asset.metadata?.videoStream
        let width = stream?.displayWidth ?? 0
        let height = stream?.displayHeight ?? 0
        let pixels = width * height
        let resolution = (width > 0 && height > 0) ? "\(width)×\(height)" : "—"
        let fileSize = asset.fileIdentity.fileSize
        let fileSizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        let bitrateVal = stream?.bitrate ?? 0
        let bitrateStr = bitrateVal > 0 ? String(format: "%.1f Mbps", Double(bitrateVal) / 1_000_000.0) : "—"
        let codec = formatCodec(stream)
        let durationSec = asset.metadata?.durationSeconds ?? 0
        let durationStr = formatDuration(durationSec)
        
        return HStack(spacing: 12) {
            // Thumbnail with QuickView on click
            Button(action: {
                onQuickView(asset.path)
            }) {
                ZStack {
                    VideoTwinThumbnailView(url: asset.path, width: 72, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 20, height: 20)
                    Image(systemName: "play.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .help("Bấm để xem trước video với thanh tua timeline")
            
            // Video Information (Clean, unboxed specs)
            VStack(alignment: .leading, spacing: 3) {
                // Line 1: File name + Best Badge
                HStack(spacing: 6) {
                    Text(asset.path.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CFinderTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if isBest {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7))
                            Text("Tốt nhất")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Color(hex: "10B981"))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(hex: "10B981").opacity(0.15))
                        .clipShape(Capsule())
                    }
                }
                
                // Line 2: Specs with smart diffing (highlighting only superior specs)
                HStack(spacing: 6) {
                    // Resolution
                    if diff.resolutionDiffers && pixels == diff.maxPixels && pixels > 0 {
                        Text("\(resolution) (Nét hơn)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CFinderTheme.primaryLight)
                    } else {
                        Text(resolution)
                            .font(.system(size: 10))
                            .foregroundStyle(CFinderTheme.textMuted)
                    }
                    
                    Text("•").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.2))
                    
                    // Duration
                    if durationSec > 0 {
                        Text(durationStr)
                            .font(.system(size: 10))
                            .foregroundStyle(CFinderTheme.textMuted)
                        Text("•").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.2))
                    }
                    
                    // File Size
                    if diff.sizeDiffers && fileSize == diff.minSize && fileSize > 0 {
                        Text("\(fileSizeStr) (Nhẹ hơn)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CFinderTheme.success)
                    } else {
                        Text(fileSizeStr)
                            .font(.system(size: 10))
                            .foregroundStyle(CFinderTheme.textMuted)
                    }
                    
                    Text("•").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.2))
                    
                    // Bitrate
                    Text(bitrateStr)
                        .font(.system(size: 10))
                        .foregroundStyle(CFinderTheme.textMuted)
                    
                    Text("•").font(.system(size: 8)).foregroundStyle(Color.white.opacity(0.2))
                    
                    // Codec
                    if diff.codecDiffers && (codec.contains("HEVC") || codec.contains("AV1")) {
                        Text("\(codec) (Nén mới)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CFinderTheme.success)
                    } else {
                        Text(codec)
                            .font(.system(size: 10))
                            .foregroundStyle(CFinderTheme.textMuted)
                    }
                }
                
                // Line 3: File Directory Path
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 8))
                        .foregroundStyle(CFinderTheme.textMuted.opacity(0.5))
                    Text(asset.path.deletingLastPathComponent().path)
                        .font(.system(size: 9))
                        .foregroundStyle(CFinderTheme.textMuted.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Trailing Actions (Aligned strictly in column)
            HStack(spacing: 8) {
                // Open Folder in Finder
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([asset.path])
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(CFinderTheme.textMuted)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Mở vị trí tệp trong Finder")
                
                // Toggle Button (Xóa / Giữ)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        onToggleRemoval(asset.id)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isMarkedForTrash ? "trash.fill" : "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text(isMarkedForTrash ? "Xóa" : "Giữ")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isMarkedForTrash ? CFinderTheme.danger : Color.white.opacity(0.06))
                    .foregroundStyle(isMarkedForTrash ? .white : Color(hex: "10B981"))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help(isMarkedForTrash ? "Bấm để giữ lại video này" : "Bấm để chọn xóa video này")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isMarkedForTrash ? CFinderTheme.danger.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.18), value: isMarkedForTrash)
    }
    
    private func formatCodec(_ s: VideoStreamMetadata?) -> String {
        guard let s else { return "—" }
        let raw = s.codec.lowercased()
        return (raw.contains("hvc") || raw.contains("hevc") || raw.contains("h265")) ? "HEVC" :
               (raw.contains("avc") || raw.contains("h264")) ? "H.264" :
               (raw.contains("av1") || raw.contains("av01")) ? "AV1" :
               (raw.contains("vp9") || raw.contains("vp09")) ? "VP9" : s.codec.uppercased()
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

// MARK: - Safe Quick Video Surface (Backed by AVPlayerLayer, 100% Crash-Free)

public struct QuickVideoSurfaceView: NSViewRepresentable {
    public let player: AVPlayer
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer as? AVPlayerLayer {
            layer.player = player
        }
    }
}

// MARK: - Video Quick Preview Modal

public struct VideoQuickPreviewModal: View {
    public let url: URL
    public let onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    @State private var isPlaying = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isMuted = false
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    
    public init(url: URL, onDismiss: @escaping () -> Void) {
        self.url = url
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    cleanupAndDismiss()
                }
            
            VStack(spacing: 0) {
                // Header Bar
                HStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 13))
                        .foregroundStyle(CFinderTheme.FeatureColor.videoTwin)
                    
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Xem trong Finder")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        cleanupAndDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(6)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "1F242C"))
                
                // Video Surface
                ZStack {
                    Color.black
                    if let p = player {
                        QuickVideoSurfaceView(player: p)
                            .onTapGesture {
                                togglePlayPause()
                            }
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 720, height: 420)
                
                // Bottom Transport & Scrubber Bar
                HStack(spacing: 12) {
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    
                    Text(formatTime(currentTime))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { newVal in
                                isSeeking = true
                                currentTime = newVal
                                let target = CMTime(seconds: newVal, preferredTimescale: 600)
                                player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                                    isSeeking = false
                                }
                            }
                        ),
                        in: 0...max(0.1, duration)
                    )
                    .tint(CFinderTheme.FeatureColor.videoTwin)
                    
                    Text(formatTime(duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Button(action: toggleMute) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "1A1E24"))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CFinderTheme.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.7), radius: 30, y: 15)
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
    }
    
    private func setupPlayer() {
        _ = url.startAccessingSecurityScopedResource()
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        self.player = p
        
        Task {
            if let d = try? await asset.load(.duration).seconds, d.isFinite, d > 0 {
                await MainActor.run { self.duration = d }
            }
        }
        
        let interval = CMTime(value: 1, timescale: 10)
        self.timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard !isSeeking else { return }
            currentTime = time.seconds
            if let currentItem = p?.currentItem, currentItem.status == .readyToPlay {
                let dur = currentItem.duration.seconds
                if dur.isFinite && dur > 0 && duration <= 0 {
                    duration = dur
                }
            }
        }
        
        p.play()
        self.isPlaying = true
    }
    
    private func teardownPlayer() {
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        url.stopAccessingSecurityScopedResource()
    }
    
    private func cleanupAndDismiss() {
        teardownPlayer()
        onDismiss()
    }
    
    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }
    
    private func toggleMute() {
        guard let p = player else { return }
        isMuted.toggle()
        p.isMuted = isMuted
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
