import Foundation

/// A group of videos that are duplicates/variants of each other.
public struct DuplicateCluster: Sendable, Identifiable, Codable {
    public let id: UUID
    public var members: [ClusterMember]
    public var representativeMatchType: MatchType
    public var overallSimilarity: Float
    public var createdAt: Date
    public var updatedAt: Date

    public var recommendedKeepID: UUID? {
        members.first(where: { $0.isRecommendedKeep })?.assetID
    }

    public var reclaimableBytes: Int64 {
        members
            .filter { !$0.isRecommendedKeep }
            .compactMap { $0.fileSize }
            .reduce(0, +)
    }

    public init(
        id: UUID = UUID(),
        members: [ClusterMember],
        representativeMatchType: MatchType,
        overallSimilarity: Float,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.members = members
        self.representativeMatchType = representativeMatchType
        self.overallSimilarity = overallSimilarity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ClusterMember: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public let assetID: UUID
    public let clusterID: UUID
    public var isRecommendedKeep: Bool
    public var qualityScore: Float?
    public var fileSize: Int64?
    public var userDecision: UserDecision

    public init(
        id: UUID = UUID(),
        assetID: UUID,
        clusterID: UUID,
        isRecommendedKeep: Bool = false,
        qualityScore: Float? = nil,
        fileSize: Int64? = nil,
        userDecision: UserDecision = .undecided
    ) {
        self.id = id
        self.assetID = assetID
        self.clusterID = clusterID
        self.isRecommendedKeep = isRecommendedKeep
        self.qualityScore = qualityScore
        self.fileSize = fileSize
        self.userDecision = userDecision
    }

    public enum UserDecision: String, Sendable, Codable {
        case undecided
        case keep
        case remove
        case ignore
    }
}
