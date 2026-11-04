import Foundation

/// A single sampled frame from a video with its fingerprint data.
public struct FrameSample: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let assetID: UUID
    /// Position as fraction 0...1 of video duration
    public let position: Double
    /// Actual timestamp in seconds
    public let timestampSeconds: Double
    public var visualFingerprint: VisualFingerprint?
    public var sharpness: Float? = nil
    /// Algorithm version used for normalization
    public let normalizationVersion: String
}

/// Multi-algorithm visual fingerprint for a frame.
public struct VisualFingerprint: Sendable, Hashable, Codable {
    /// 64-bit dHash
    public var dHash: UInt64?
    /// 64-element DCT pHash vector stored as hex
    public var pHash: [UInt8]?
    /// Vision FeaturePrint embedding (variable length)
    public var featurePrint: [Float]?
    /// Dominant color signature (compact histogram)
    public var colorSignature: [UInt8]?
    /// Algorithm versions for cache invalidation
    public let algorithmVersions: AlgorithmVersions
}

public struct AlgorithmVersions: Sendable, Hashable, Codable {
    public var dHash: String = "v1"
    public var pHash: String = "v1"
    public var featurePrint: String = "v1"
    public var colorSignature: String = "v1"
    public var normalization: String = "v1"
}
