import Foundation

/// Result of comparing two video assets.
public struct MatchResult: Sendable, Identifiable, Codable {
    public let id: UUID
    public let assetAID: UUID
    public let assetBID: UUID

    // MARK: - Multi-dimensional scores
    public let visualScore: Float
    public let timelineScore: Float
    public let audioScore: Float?
    public let durationScore: Float
    public let metadataScore: Float
    public let coverageScore: Float

    // MARK: - Classification
    public let matchType: MatchType
    public let confidence: MatchConfidence

    // MARK: - Timeline alignment
    public let alignment: AlignmentResult?

    // MARK: - Coverage (for partial/contained)
    public let coverageA: Float   // 0...1
    public let coverageB: Float   // 0...1

    // MARK: - Meta
    public let analysisVersion: String
    public let analysedAt: Date

    public init(
        id: UUID = UUID(),
        assetAID: UUID,
        assetBID: UUID,
        visualScore: Float,
        timelineScore: Float,
        audioScore: Float?,
        durationScore: Float,
        metadataScore: Float,
        coverageScore: Float,
        matchType: MatchType,
        confidence: MatchConfidence,
        alignment: AlignmentResult?,
        coverageA: Float,
        coverageB: Float,
        analysisVersion: String,
        analysedAt: Date = Date()
    ) {
        self.id = id
        self.assetAID = assetAID
        self.assetBID = assetBID
        self.visualScore = visualScore
        self.timelineScore = timelineScore
        self.audioScore = audioScore
        self.durationScore = durationScore
        self.metadataScore = metadataScore
        self.coverageScore = coverageScore
        self.matchType = matchType
        self.confidence = confidence
        self.alignment = alignment
        self.coverageA = coverageA
        self.coverageB = coverageB
        self.analysisVersion = analysisVersion
        self.analysedAt = analysedAt
    }
}

extension MatchResult {
    public static func exact(_ a: UUID, _ b: UUID) -> MatchResult {
        MatchResult(id: UUID(), assetAID: a, assetBID: b, visualScore: 1, timelineScore: 1, audioScore: nil, durationScore: 1, metadataScore: 1, coverageScore: 1, matchType: .exact, confidence: .certain, alignment: nil, coverageA: 1, coverageB: 1, analysisVersion: "sha256-v1", analysedAt: Date())
    }
}

public enum MatchType: String, Sendable, Hashable, Codable, CaseIterable {
    case exact                // EXACT_DUPLICATE
    case nearDuplicate        // NEAR_DUPLICATE
    case reencoded            // REENCODED
    case resolutionVariant    // RESOLUTION_VARIANT
    case fpsVariant           // FPS_VARIANT
    case croppedVariant       // CROPPED_VARIANT
    case trimmed              // TRIMMED_VARIANT
    case containedClip        // CONTAINED_CLIP
    case partialMatch         // PARTIAL_MATCH
    case possibleMatch        // POSSIBLE_MATCH
    case different            // NOT_MATCH
}

public enum MatchConfidence: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case veryHigh
    case certain

    public static func < (lhs: MatchConfidence, rhs: MatchConfidence) -> Bool {
        let order: [MatchConfidence] = [.low, .medium, .high, .veryHigh, .certain]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}
