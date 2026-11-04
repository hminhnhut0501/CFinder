import Foundation

/// All similarity thresholds in one place.
/// NEVER hardcode these inline — always reference this struct.
/// Values are calibrated against the ground-truth corpus.
public struct SimilarityConfiguration: Sendable, Codable {
    // MARK: - Candidate filtering thresholds
    /// Duration ratio below which candidates are rejected (full-length mode)
    public var durationRatioMin: Float = 0.95
    /// Duration tolerance in seconds for candidates close in length
    public var durationToleranceSeconds: Double = 2.0
    /// Coarse visual similarity below which candidate is rejected early
    public var coarseRejectThreshold: Float = 0.25

    // MARK: - Match classification thresholds
    /// Minimum visual score to consider a possible match
    public var possibleThreshold: Float = 0.70
    /// Minimum visual score for near-duplicate classification
    public var nearDuplicateThreshold: Float = 0.88
    /// Minimum visual score for high-confidence match
    public var highConfidenceThreshold: Float = 0.95

    // MARK: - Adaptive sampling
    public var coarseSampleCount: Int = 8
    public var mediumSampleCount: Int = 12
    public var fineSampleCount: Int = 20
    public var deepSampleCount: Int = 32

    /// Minimum aligned frames to trust timeline alignment
    public var minimumAlignedSamples: Int = 4

    // MARK: - Early rejection
    /// If first N frames all below this, reject without decoding more
    public var earlyRejectFrameThreshold: Float = 0.20
    public var earlyRejectFrameCount: Int = 3

    public var alignmentToleranceSeconds: Double = 0.5
    public var maxCandidatesPerAsset: Int = 64
    public var coarseCandidateDistance: Int = 16

    // MARK: - Coverage
    /// Minimum coverage of the shorter video to classify as CONTAINED_CLIP
    public var containedClipMinCoverage: Float = 0.80

    // MARK: - Auto-selection safety
    /// Only pre-select candidates for removal if confidence >= this
    public var autoSelectMinConfidence: MatchConfidence = .veryHigh
    /// Only pre-select if precision on this match type is validated >= 99%
    public var autoSelectRequiresValidation: Bool = true

    public init() {}

    public static let `default` = SimilarityConfiguration()
}
