import Foundation

/// Detailed quality metrics for a video asset.
public struct QualityMetrics: Sendable, Hashable, Codable {
    public let assetID: UUID

    // MARK: - Technical
    public let width: Int
    public let height: Int
    public let bitDepth: Int?
    public let isHDR: Bool
    public let codec: String
    public let videoBitrate: Int64?
    public let fps: Double
    public let bitsPerPixel: Double?  // videoBitrate / (width * height * fps)

    // MARK: - Perceptual (computed via frame analysis)
    /// Sharpness score 0...1 (Laplacian variance normalized)
    public let sharpness: Float?
    /// Blocking artifact score 0...1 (lower = better)
    public let blocking: Float?
    /// Noise score 0...1 (lower = better)
    public let noise: Float?
    /// Compression artifact score 0...1 (lower = better)
    public let compressionArtifacts: Float?

    // MARK: - Audio
    public let audioCodec: String?
    public let audioChannels: Int?
    public let audioSampleRate: Double?
    public let audioBitrate: Int64?

    // MARK: - Suspicion flags
    public let upscaleSuspicion: UpscaleSuspicion

    // MARK: - Overall
    /// Composite quality score 0...100
    public let overallScore: Float

    /// Human-readable reasons for the score
    public let reasons: [QualityReason]
}

public enum UpscaleSuspicion: String, Sendable, Hashable, Codable {
    case none
    case possible
    case likely
}

public struct QualityReason: Sendable, Hashable, Codable {
    public let aspect: String
    public let description: String
    public let impact: ReasonImpact

    public enum ReasonImpact: String, Sendable, Hashable, Codable {
        case positive, negative, neutral
    }
}
