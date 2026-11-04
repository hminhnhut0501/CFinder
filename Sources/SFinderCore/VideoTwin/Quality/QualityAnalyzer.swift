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
        let bitrate = vs?.bitrate

        let pixels = Float(width * height)
        var bpp: Double? = nil
        if let b = bitrate, pixels > 0, fps > 0 {
            bpp = Double(b) / Double(pixels * Float(fps))
        }

        let resScore = calculateResolutionScore(vs)
        let (bitrateScore, codecScore) = calculateBitrateAndCodecScore(vs, container: meta.container)
        let audioScore = calculateAudioScore(meta.audioStream)

        let rawScore = (resScore * 0.4) + (codecScore * 0.2) + (bitrateScore * 0.3) + (audioScore * 0.1)

        let upscaleSuspicion = detectUpscaleSuspicion(vs)
        let sharpnessValues = asset.fingerprints.compactMap(\.sharpness).sorted()
        let sharpness = sharpnessValues.isEmpty ? nil : sharpnessValues[sharpnessValues.count / 2]
        let measuredScore = sharpness.map { rawScore * 0.9 + $0 * 0.1 } ?? rawScore
        let finalScore = (upscaleSuspicion != .none) ? measuredScore * 0.6 : measuredScore

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
        let pixels = Float(v.width * v.height)
        let refPixels: Float = 8_294_400
        var score = min(1.0, pixels / refPixels)
        if v.isHDR || (v.bitDepth ?? 8) > 8 { score = min(1.0, score * 1.1) }
        return score
    }

    private func calculateBitrateAndCodecScore(_ video: VideoStreamMetadata?, container: String) -> (Float, Float) {
        let codecStr = video?.codec.lowercased() ?? "unknown"
        let bitrate = Float(video?.bitrate ?? 0)

        let codecScore: Float
        let refBitrate: Float

        if codecStr.contains("hevc") || codecStr.contains("h265") || codecStr.contains("hvc1") {
            codecScore = 1.0; refBitrate = 15_000_000
        } else if codecStr.contains("vp9") || codecStr.contains("av1") {
            codecScore = 0.9; refBitrate = 15_000_000
        } else if codecStr.contains("h264") || codecStr.contains("avc") {
            codecScore = 0.8; refBitrate = 25_000_000
        } else {
            codecScore = 0.5; refBitrate = 30_000_000
        }
        let bScore = bitrate > 0 ? min(1.0, bitrate / refBitrate) : 0.5
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

    private func detectUpscaleSuspicion(_ video: VideoStreamMetadata?) -> UpscaleSuspicion {
        guard let v = video, v.width > 0, v.height > 0 else { return .none }
        let pixels = Float(v.width * v.height)
        if let bitrate = v.bitrate, bitrate > 0 {
            let bpp = Float(bitrate) / (pixels * Float(max(1, v.nominalFPS)))
            if bpp < 0.01 { return .likely }
        }
        if v.width % 2 != 0 || v.height % 2 != 0 { return .possible }
        return .none
    }
}
