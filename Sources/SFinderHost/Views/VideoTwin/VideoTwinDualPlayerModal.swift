import SwiftUI
import AVKit
import SFinderCore

// MARK: - Player Surface

public struct PlayerSurface: NSViewRepresentable {
    public let player: AVPlayer
    
    public init(player: AVPlayer) {
        self.player = player
    }
    
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

// MARK: - Dual Playback Coordinator

@MainActor
public final class DualPlaybackCoordinator: ObservableObject {
    public let playerA = AVPlayer()
    public let playerB = AVPlayer()
    
    @Published public var time: Double = 0.0
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var isReady: Bool = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var startTime: Double = 0.0
    @Published public private(set) var endTime: Double = 0.0
    
    private var offset: Double = 0.0
    private var isScrubbing: Bool = false
    private var isSeeking: Bool = false
    private var generation: Int = 0
    private var seekTask: Task<Void, Never>?
    private var timer: Timer?
    
    public init() {
        playerA.automaticallyWaitsToMinimizeStalling = false
        playerB.automaticallyWaitsToMinimizeStalling = false
    }
    
    public func load(assetA: VideoAsset, assetB: VideoAsset, offset: Double) async {
        await load(urlA: assetA.path, urlB: assetB.path, offset: offset)
    }
    
    public func load(urlA: URL, urlB: URL, offset: Double = 0.0) async {
        self.offset = offset
        self.errorMessage = nil
        self.isReady = false
        
        let left = AVURLAsset(url: urlA)
        let right = AVURLAsset(url: urlB)
        
        do {
            let durationA = try await left.load(.duration).seconds
            let durationB = try await right.load(.duration).seconds
            
            guard offset.isFinite, durationA.isFinite, durationB.isFinite else {
                self.errorMessage = "Không thể đọc thời lượng của hai video."
                return
            }
            
            startTime = max(0, -offset)
            endTime = min(durationA, durationB - offset)
            
            guard endTime > startTime else {
                self.errorMessage = "Hai video không có đoạn thời gian trùng lặp để phát đồng thời."
                return
            }
            
            playerA.replaceCurrentItem(with: AVPlayerItem(asset: left))
            playerB.replaceCurrentItem(with: AVPlayerItem(asset: right))
            playerB.isMuted = true
            
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while playerA.currentItem?.status != .readyToPlay || playerB.currentItem?.status != .readyToPlay {
                try Task.checkCancellation()
                if playerA.currentItem?.status == .failed || playerB.currentItem?.status == .failed || ContinuousClock.now >= deadline {
                    self.errorMessage = "Trình phát video chưa sẵn sàng hoặc codec chưa hỗ trợ."
                    return
                }
                try await Task.sleep(for: .milliseconds(30))
            }
            
            isReady = true
            time = startTime
            seek(to: startTime, resume: false)
            startPeriodicTimer()
        } catch is CancellationError {
            close()
        } catch {
            self.errorMessage = "Lỗi khởi tạo trình phát: \(error.localizedDescription)"
        }
    }
    
    public func togglePlayPause() {
        guard isReady else { return }
        if isPlaying {
            isPlaying = false
            playerA.pause()
            playerB.pause()
        } else {
            if time >= endTime - 0.05 {
                time = startTime
            }
            seek(to: time, resume: true)
        }
    }
    
    public func scrub(isEditing: Bool) {
        isScrubbing = isEditing
        if isEditing {
            playerA.pause()
            playerB.pause()
        } else {
            seek(to: time, resume: isPlaying)
        }
    }
    
    public func seek(to targetSec: Double, resume: Bool) {
        generation += 1
        let currentGen = generation
        seekTask?.cancel()
        
        playerA.currentItem?.cancelPendingSeeks()
        playerB.currentItem?.cancelPendingSeeks()
        playerA.pause()
        playerB.pause()
        
        let bounded = max(startTime, min(endTime, targetSec))
        time = bounded
        isSeeking = true
        
        seekTask = Task {
            let leftOk = await playerA.seek(to: CMTime(seconds: bounded, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled, currentGen == generation else { return }
            
            let rightOk = await playerB.seek(to: CMTime(seconds: bounded + offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard !Task.isCancelled, currentGen == generation else { return }
            
            isSeeking = false
            guard leftOk, rightOk else {
                self.isPlaying = false
                return
            }
            
            self.isPlaying = resume
            if resume {
                let hostTime = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(seconds: 0.08, preferredTimescale: 600))
                playerA.setRate(1.0, time: CMTime(seconds: bounded, preferredTimescale: 600), atHostTime: hostTime)
                playerB.setRate(1.0, time: CMTime(seconds: bounded + offset, preferredTimescale: 600), atHostTime: hostTime)
            }
        }
    }
    
    private func startPeriodicTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    private func tick() {
        guard isReady, isPlaying, !isScrubbing, !isSeeking else { return }
        let current = playerA.currentTime().seconds
        guard current.isFinite else { return }
        
        time = min(endTime, max(startTime, current))
        if current >= endTime - 0.03 {
            isPlaying = false
            playerA.pause()
            playerB.pause()
        }
    }
    
    public func close() {
        timer?.invalidate()
        timer = nil
        generation += 1
        seekTask?.cancel()
        playerA.currentItem?.cancelPendingSeeks()
        playerB.currentItem?.cancelPendingSeeks()
        playerA.pause()
        playerB.pause()
        playerA.replaceCurrentItem(with: nil)
        playerB.replaceCurrentItem(with: nil)
        isPlaying = false
        isReady = false
    }
    
    deinit {
        timer?.invalidate()
        playerA.replaceCurrentItem(with: nil)
        playerB.replaceCurrentItem(with: nil)
    }
}

// MARK: - Dual Player Modal View

public struct VideoTwinDualPlayerModal: View {
    public let assetA: VideoAsset
    public let assetB: VideoAsset
    public let offset: Double
    public let onDismiss: () -> Void
    
    @StateObject private var playback = DualPlaybackCoordinator()
    
    public init(assetA: VideoAsset, assetB: VideoAsset, offset: Double, onDismiss: @escaping () -> Void) {
        self.assetA = assetA
        self.assetB = assetB
        self.offset = offset
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            CFinderTheme.backgroundBase
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "film.stack")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CFinderTheme.primaryLight)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("So sánh trực tiếp video song song")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CFinderTheme.textPrimary)
                        
                        Text("Đồng bộ khung hình theo thời gian thực • Âm thanh từ video bên trái")
                            .font(.system(size: 12))
                            .foregroundStyle(CFinderTheme.textMuted)
                    }
                    
                    Spacer()
                    
                    // Offset pill
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11))
                        Text(String(format: "Độ lệch: %@%.2fs", offset >= 0 ? "+" : "", offset))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(CFinderTheme.cardSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(CFinderTheme.cardBorder, lineWidth: 1))
                    .foregroundStyle(CFinderTheme.textAccent)
                    
                    Button(action: {
                        playback.close()
                        onDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CFinderTheme.textMuted)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Two video screens
                HStack(spacing: 14) {
                    videoScreen(title: assetA.path.lastPathComponent, player: playback.playerA, isLeft: true)
                    videoScreen(title: assetB.path.lastPathComponent, player: playback.playerB, isLeft: false)
                }
                .padding(.horizontal, 20)
                
                // Controls bar
                VStack(spacing: 8) {
                    if let err = playback.errorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(CFinderTheme.danger)
                    }
                    
                    HStack(spacing: 16) {
                        Button(action: { playback.togglePlayPause() }) {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(CFinderTheme.primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!playback.isReady)
                        
                        Text(formatTime(playback.time))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(CFinderTheme.textPrimary)
                            .frame(width: 50, alignment: .leading)
                        
                        Slider(
                            value: $playback.time,
                            in: playback.startTime...max(playback.startTime + 0.001, playback.endTime),
                            onEditingChanged: playback.scrub
                        )
                        .tint(CFinderTheme.primaryLight)
                        .disabled(!playback.isReady)
                        
                        Text(formatTime(playback.endTime))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(CFinderTheme.textMuted)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 20)
                }
                
                // Tech Specs comparison
                VideoTwinMetricsRow(assetA: assetA, assetB: assetB)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 840, minHeight: 600)
        .task {
            await playback.load(assetA: assetA, assetB: assetB, offset: offset)
        }
        .onDisappear {
            playback.close()
        }
    }
    
    private func videoScreen(title: String, player: AVPlayer, isLeft: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(isLeft ? CFinderTheme.primaryLight : Color(hex: "F472B6"))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CFinderTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isLeft {
                    Text("Âm thanh chính")
                        .font(.system(size: 10))
                        .foregroundStyle(CFinderTheme.primaryLight)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CFinderTheme.primaryLight.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            PlayerSurface(player: player)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(CFinderTheme.cardBorder, lineWidth: 1)
                )
                .frame(minHeight: 260)
        }
        .padding(12)
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatTime(_ sec: Double) -> String {
        guard sec.isFinite, sec >= 0 else { return "0:00" }
        let total = Int(sec)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Dual Player Modal for URLs (Video Inspector)

public struct VideoInspectorDualPlayerModal: View {
    public let urlA: URL
    public let urlB: URL
    public let onDismiss: () -> Void
    
    @StateObject private var playback = DualPlaybackCoordinator()
    
    public init(urlA: URL, urlB: URL, onDismiss: @escaping () -> Void) {
        self.urlA = urlA
        self.urlB = urlB
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            CFinderTheme.backgroundBase
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "film.stack")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CFinderTheme.primaryLight)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("So sánh trực tiếp video song song")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CFinderTheme.textPrimary)
                        
                        Text("Đồng bộ khung hình theo thời gian thực • Âm thanh từ video bên trái")
                            .font(.system(size: 11))
                            .foregroundStyle(CFinderTheme.textMuted)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        playback.close()
                        onDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CFinderTheme.textMuted)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Two video screens
                HStack(spacing: 14) {
                    videoScreen(title: urlA.lastPathComponent, player: playback.playerA, isLeft: true)
                    videoScreen(title: urlB.lastPathComponent, player: playback.playerB, isLeft: false)
                }
                .padding(.horizontal, 20)
                
                // Controls bar
                VStack(spacing: 8) {
                    if let err = playback.errorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(CFinderTheme.danger)
                    }
                    
                    HStack(spacing: 16) {
                        Button(action: { playback.togglePlayPause() }) {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(CFinderTheme.primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!playback.isReady)
                        
                        Text(formatTime(playback.time))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(CFinderTheme.textPrimary)
                            .frame(width: 50, alignment: .leading)
                        
                        Slider(
                            value: $playback.time,
                            in: playback.startTime...max(playback.startTime + 0.001, playback.endTime),
                            onEditingChanged: playback.scrub
                        )
                        .tint(CFinderTheme.primaryLight)
                        .disabled(!playback.isReady)
                        
                        Text(formatTime(playback.endTime))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(CFinderTheme.textMuted)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(minWidth: 840, minHeight: 560)
        .task {
            await playback.load(urlA: urlA, urlB: urlB, offset: 0.0)
        }
        .onDisappear {
            playback.close()
        }
    }
    
    private func videoScreen(title: String, player: AVPlayer, isLeft: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(isLeft ? CFinderTheme.primaryLight : Color(hex: "F472B6"))
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CFinderTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isLeft {
                    Text("Âm thanh chính")
                        .font(.system(size: 10))
                        .foregroundStyle(CFinderTheme.primaryLight)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(CFinderTheme.primaryLight.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
            PlayerSurface(player: player)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(CFinderTheme.cardBorder, lineWidth: 1)
                )
                .frame(minHeight: 260)
        }
        .padding(12)
        .background(CFinderTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatTime(_ sec: Double) -> String {
        guard sec.isFinite, sec >= 0 else { return "0:00" }
        let total = Int(sec)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
