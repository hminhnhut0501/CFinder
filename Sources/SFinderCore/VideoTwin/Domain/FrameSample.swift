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
    /// 64-element DCT pHash vector
    public var pHash: [UInt8]?
    /// 64-bit dHash of the center safe region (strips outer 18% to ignore corner logos/captions)
    public var centerDHash: UInt64?
    /// 64-element DCT pHash of the center safe region
    public var centerPHash: [UInt8]?
    /// 64-bit dHash of the deep zoom/crop center region (~55% zoom into center or 9:16 vertical crop)
    public var zoomDHash: UInt64?
    /// 64-element DCT pHash of the deep zoom/crop center region
    public var zoomPHash: [UInt8]?
    /// 2x2 grid pHashes (4 regions) for partial-occlusion robustness against large overlays/text
    public var gridPHashes: [[UInt8]]?
    /// Vision FeaturePrint embedding (variable length)
    public var featurePrint: [Float]?
    /// Dominant color signature (compact histogram)
    public var colorSignature: [UInt8]?
    /// Algorithm versions for cache invalidation
    public let algorithmVersions: AlgorithmVersions

    public init(
        dHash: UInt64? = nil,
        pHash: [UInt8]? = nil,
        centerDHash: UInt64? = nil,
        centerPHash: [UInt8]? = nil,
        zoomDHash: UInt64? = nil,
        zoomPHash: [UInt8]? = nil,
        gridPHashes: [[UInt8]]? = nil,
        featurePrint: [Float]? = nil,
        colorSignature: [UInt8]? = nil,
        algorithmVersions: AlgorithmVersions = AlgorithmVersions()
    ) {
        self.dHash = dHash
        self.pHash = pHash
        self.centerDHash = centerDHash
        self.centerPHash = centerPHash
        self.zoomDHash = zoomDHash
        self.zoomPHash = zoomPHash
        self.gridPHashes = gridPHashes
        self.featurePrint = featurePrint
        self.colorSignature = colorSignature
        self.algorithmVersions = algorithmVersions
    }
}

public struct AlgorithmVersions: Sendable, Hashable, Codable {
    public var dHash: String = "v1"
    public var pHash: String = "v1"
    public var featurePrint: String = "v1"
    public var colorSignature: String = "v1"
    public var normalization: String = "v1"

    public init() {}
}
