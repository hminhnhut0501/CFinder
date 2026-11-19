import Foundation
import CoreMedia
import OSLog

public actor QualityAnalyzer {
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "quality")

    public init() {}

    func analyze(asset: VideoAsset) -> QualityMetrics {
        guard let meta = asset.metadata else {
            return QualityMetrics(
                assetID: asset.id,
                width: 0, height: 0, bitDepth: nil, isHDR: false,
                codec: "unknown", videoBitrate: nil, fps: 0, bitsPerPixel: nil,
                sharpness: nil, blocking: nil, noise: nil, compressionArtifacts: nil,
                audioCodec: nil, audioChannels: nil, audioSampleRate: nil, audioBitrate: nil,
                upscaleSuspicion: .none,
                overallScore: 0,
                reasons: [QualityReason(aspect: "Metadata", description: "Missing metadata", impact: .negative)]
            )
        }

        let vs = meta.videoStream
        let width = vs?.width ?? 0
        let height = vs?.height ?? 0
        let fps = vs?.nominalFPS ?? 30.0
        
        // Effective bitrate with fallback from file size & duration
        var bitrate = vs?.bitrate
        if (bitrate == nil || bitrate == 0), meta.fileSize > 0, meta.durationSeconds > 0 {
            let totalBps = Int64(Double(meta.fileSize * 8) / max(0.1, meta.durationSeconds))
            let audioBps = meta.audioStream?.bitrate ?? 128_000
            bitrate = max(100_000, totalBps - audioBps)
        }

        let pixels = Float(width * height)
        var bpp: Double? = nil
        if let b = bitrate, pixels > 0, fps > 0 {
            bpp = Double(b) / Double(pixels * Float(fps))
        }

        let resScore = calculateResolutionScore(vs)
        let (bitrateScore, codecScore) = calculateBitrateAndCodecScore(vs, container: meta.container, effectiveBitrate: bitrate)
        let audioScore = calculateAudioScore(meta.audioStream)

        // Quality First: Resolution dominates at 50%, Bitrate 25%, Codec 15%, Audio 10%
        let rawScore = (resScore * 0.50) + (bitrateScore * 0.25) + (codecScore * 0.15) + (audioScore * 0.10)

        let upscaleSuspicion = detectUpscaleSuspicion(vs, effectiveBitrate: bitrate)
        let sharpnessValues = asset.fingerprints.compactMap(\.sharpness).sorted()
        let sharpness = sharpnessValues.isEmpty ? nil : sharpnessValues[sharpnessValues.count / 2]
        let measuredScore = sharpness.map { rawScore * 0.9 + $0 * 0.1 } ?? rawScore
        let finalScore = (upscaleSuspicion == .likely) ? measuredScore * 0.88 : measuredScore

        var reasons: [QualityReason] = []
        if upscaleSuspicion == .likely {
            reasons.append(QualityReason(aspect: "Upscale", description: "Suspiciously low bitrate for resolution", impact: .negative))
        }
        if let sharpness {
            reasons.append(QualityReason(aspect: "Sharpness", description: "Measured frame sharpness: \(Int(sharpness * 100))/100", impact: .neutral))
        }
        if (vs?.isHDR ?? false) || (vs?.bitDepth ?? 8) > 8 {
            reasons.append(QualityReason(aspect: "Color", description: "HDR / 10-bit color depth", impact: .positive))
        }

        return QualityMetrics(
            assetID: asset.id,
            width: width,
            height: height,
            bitDepth: vs?.bitDepth,
            isHDR: vs?.isHDR ?? false,
            codec: vs?.codec ?? "unknown",
            videoBitrate: bitrate,
            fps: fps,
            bitsPerPixel: bpp,
            sharpness: sharpness,
            blocking: nil,
            noise: nil,
            compressionArtifacts: nil,
            audioCodec: meta.audioStream?.codec,
            audioChannels: meta.audioStream?.channels,
            audioSampleRate: meta.audioStream?.sampleRate,
            audioBitrate: meta.audioStream?.bitrate,
            upscaleSuspicion: upscaleSuspicion,
            overallScore: finalScore * 100, // 0...100
            reasons: reasons
        )
    }

    private func calculateResolutionScore(_ video: VideoStreamMetadata?) -> Float {
        guard let v = video, v.width > 0, v.height > 0 else { return 0 }
        let w = max(v.displayWidth, v.width)
        let h = max(v.displayHeight, v.height)
        let pixels = Float(w * h)
        
        // Tiered resolution scoring reflecting real-world human perception
        let score: Float
        if pixels >= 8_000_000 {        // 4K UHD (3840×2160 = 8.29M)
            score = 1.00
        } else if pixels >= 3_500_000 {  // 1440p QHD (2560×1440 = 3.68M)
            score = 0.88
        } else if pixels >= 1_900_000 {  // 1080p FHD (1920×1080 = 2.07M)
            score = 0.78
        } else if pixels >= 900_000 {   // 720p HD (1280×720 = 0.92M)
            score = 0.50
        } else if pixels >= 380_000 {   // 480p SD (854×480 = 0.41M)
            score = 0.30
        } else {
            score = max(0.10, pixels / 1_500_000)
        }
        
        var adjusted = score
        if v.isHDR || (v.bitDepth ?? 8) > 8 {
            adjusted = min(1.0, adjusted * 1.08)
        }
        return adjusted
    }

    private func calculateBitrateAndCodecScore(_ video: VideoStreamMetadata?, container: String, effectiveBitrate: Int64?) -> (Float, Float) {
        let codecStr = video?.codec.lowercased() ?? "unknown"
        let bitrate = Float(effectiveBitrate ?? video?.bitrate ?? 0)

        let codecScore: Float
        let refBitrate: Float

        if codecStr.contains("hevc") || codecStr.contains("h265") || codecStr.contains("hvc1") {
            codecScore = 1.0; refBitrate = 15_000_000
        } else if codecStr.contains("vp9") || codecStr.contains("av1") {
            codecScore = 0.95; refBitrate = 15_000_000
        } else if codecStr.contains("h264") || codecStr.contains("avc") {
            codecScore = 0.80; refBitrate = 25_000_000
        } else {
            codecScore = 0.50; refBitrate = 30_000_000
        }
        let bScore = bitrate > 0 ? min(1.0, max(0.2, bitrate / refBitrate)) : 0.5
        return (bScore, codecScore)
    }

    private func calculateAudioScore(_ audio: AudioStreamMetadata?) -> Float {
        guard let a = audio else { return 0 }
        let channelScore = min(1.0, Float(a.channels) / 6.0)
        let bitrate = Float(a.bitrate ?? 0)
        let refBitrate: Float = 256_000
        let bScore = bitrate > 0 ? min(1.0, bitrate / (refBitrate * max(1, Float(a.channels)/2.0))) : 0.5
        return (channelScore * 0.4) + (bScore * 0.6)
    }

    private func detectUpscaleSuspicion(_ video: VideoStreamMetadata?, effectiveBitrate: Int64?) -> UpscaleSuspicion {
        guard let v = video, v.width > 0, v.height > 0 else { return .none }
        let pixels = Float(max(v.displayWidth, v.width) * max(v.displayHeight, v.height))
        // Only inspect if high resolution (1080p+) and bitrate is severely starved beyond reasonable limits
        if pixels >= 1_900_000, let bitrate = effectiveBitrate, bitrate > 0 {
            let fps = Float(max(1.0, v.nominalFPS))
            let bpp = Float(bitrate) / (pixels * fps)
            let codecStr = v.codec.lowercased()
            let isModern = codecStr.contains("hevc") || codecStr.contains("h265") || codecStr.contains("av1") || codecStr.contains("vp9")
            let threshold: Float = isModern ? 0.003 : 0.005
            if bpp < threshold { return .likely }
        }
        return .none
    }
}
