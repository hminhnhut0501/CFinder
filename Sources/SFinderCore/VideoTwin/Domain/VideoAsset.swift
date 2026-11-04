import Foundation

/// Represents a logical video file in the library.
/// Uses UUID as primary identity, NOT absolute path.
public struct VideoAsset: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var path: URL
    public let fileIdentity: FileIdentity
    public var metadata: VideoMetadata?
    public var audioMetadata: AudioStreamMetadata?
    public var fingerprints: [FrameSample]
    public var audioFingerprint: AudioFingerprint?
    public var quality: QualityMetrics?
    public var watermark: WatermarkAssessment?
    public var analysisState: AnalysisState
    public var errorState: AnalysisError?

    public init(
        id: UUID = UUID(),
        path: URL,
        fileIdentity: FileIdentity,
        analysisState: AnalysisState = .discovered
    ) {
        self.id = id
        self.path = path
        self.fileIdentity = fileIdentity
        self.fingerprints = []
        self.analysisState = analysisState
    }
}

public enum AnalysisState: String, Sendable, Codable {
    case discovered
    case identityResolved
    case metadataReady
    case coarseFingerprintReady
    case fineFingerprintReady
    case matched
    case qualityAnalyzed
    case failed
}

public enum AnalysisError: String, Sendable, Codable {
    case probeFailed
    case decodeFailed
    case insufficientVisualEvidence
    case unsupportedCodec
    case missingFile
    case permissionDenied
    case analysisFailed
}
