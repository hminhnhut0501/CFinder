import Foundation

/// Deterministic complete-link partition: every pair in a cluster needs direct evidence.
public actor ClusterEngine {
    let config: SimilarityConfiguration
    public init(config: SimilarityConfiguration = .default) { self.config = config }

    public func cluster(matches: [MatchResult], certifiedExactGroups: [[UUID]] = []) -> [DuplicateCluster] {
        var edges: [UUID: [UUID: MatchResult]] = [:]
        for match in matches where match.confidence >= .high && match.matchType != .different {
            if let old = edges[match.assetAID]?[match.assetBID], old.visualScore >= match.visualScore { continue }
            edges[match.assetAID, default: [:]][match.assetBID] = match
            edges[match.assetBID, default: [:]][match.assetAID] = match
        }
        var groups = certifiedExactGroups.filter { $0.count > 1 }.map { $0.sorted { $0.uuidString < $1.uuidString } }.sorted { $0[0].uuidString < $1[0].uuidString }
        var membership: [UUID: Int] = [:]
        var certificate: [UUID: Int] = [:]
        for i in groups.indices { for asset in groups[i] { membership[asset] = i; certificate[asset] = i } }
        let ordered = edges.keys.sorted {
            let degreeA = edges[$0]?.count ?? 0, degreeB = edges[$1]?.count ?? 0
            return degreeA == degreeB ? $0.uuidString < $1.uuidString : degreeA > degreeB
        }
        for asset in ordered where certificate[asset] == nil {
            let candidates = Set((edges[asset] ?? [:]).keys.compactMap { membership[$0] }).sorted()
            if let index = candidates.first(where: { i in groups[i].allSatisfy { edges[asset]?[$0] != nil } }) {
                groups[index].append(asset); membership[asset] = index
            } else { membership[asset] = groups.count; groups.append([asset]) }
        }
        return groups.filter { $0.count > 1 }.map { group in
            let id = UUID(), now = Date()
            let memberSet = Set(group)
            let evidence = group.flatMap { asset in
                (edges[asset] ?? [:]).compactMap { peer, match in
                    memberSet.contains(peer) && asset.uuidString < peer.uuidString ? match : nil
                }
            }
            let allExact = certificate[group[0]] != nil && group.allSatisfy { certificate[$0] == certificate[group[0]] }
            let counts = Dictionary(grouping: evidence, by: \.matchType).mapValues(\.count)
            let type = counts.keys.sorted { counts[$0] == counts[$1] ? $0.rawValue < $1.rawValue : counts[$0, default: 0] > counts[$1, default: 0] }.first ?? .nearDuplicate
            return DuplicateCluster(id: id, members: group.map { ClusterMember(id: UUID(), assetID: $0, clusterID: id, isRecommendedKeep: false, qualityScore: nil, fileSize: nil, userDecision: .undecided) }, representativeMatchType: allExact ? .exact : (type == .exact && evidence.contains { $0.matchType != .exact } ? .nearDuplicate : type), overallSimilarity: allExact ? 1 : evidence.map(\.visualScore).reduce(0, +) / Float(max(1, evidence.count)), createdAt: now, updatedAt: now)
        }
    }
}
