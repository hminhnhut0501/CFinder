import Foundation
import OSLog

public actor BestCopyRecommender {
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "quality")
    let analyzer: QualityAnalyzer

    public init(analyzer: QualityAnalyzer = QualityAnalyzer()) {
        self.analyzer = analyzer
    }

    public struct Preferences: Sendable {
        public var preferAppleNative: Bool = true
        public var preferSpaceSaving: Bool = true
        public var qualityEquivalenceThreshold: Float = 5.0 // 0...100 scale now

        public init(preferAppleNative: Bool = true, preferSpaceSaving: Bool = true, qualityEquivalenceThreshold: Float = 5.0) {
            self.preferAppleNative = preferAppleNative
            self.preferSpaceSaving = preferSpaceSaving
            self.qualityEquivalenceThreshold = qualityEquivalenceThreshold
        }
    }

    public func recommend(for cluster: DuplicateCluster, assets: [UUID: VideoAsset], prefs: Preferences = Preferences()) async -> DuplicateCluster {
        guard cluster.members.count > 1 else { return cluster }

        var evaluatedMembers: [(member: ClusterMember, asset: VideoAsset, metrics: QualityMetrics)] = []

        for member in cluster.members {
            guard let asset = assets[member.assetID] else { continue }
            let metrics = await analyzer.analyze(asset: asset)
            evaluatedMembers.append((member, asset, metrics))
        }

        guard !evaluatedMembers.isEmpty else { return cluster }

        let memberIDs = Set(evaluatedMembers.map { $0.asset.id })
        let longestDuration = evaluatedMembers.compactMap { $0.asset.metadata?.durationSeconds }.max() ?? 0
        let cleanIDs = Set(evaluatedMembers.compactMap { item -> UUID? in
            guard let mark = item.asset.watermark, mark.status == .detected, !mark.dismissed,
                  mark.comparableAlternative, memberIDs.contains(mark.peerID), let peer = assets[mark.peerID],
                  peer.watermark?.status != .detected,
                  (peer.metadata?.durationSeconds ?? 0) >= longestDuration * 0.98 else { return nil }
            return peer.id
        })
        func score(_ item: (member: ClusterMember, asset: VideoAsset, metrics: QualityMetrics)) -> Float {
            guard let mark = item.asset.watermark, cleanIDs.contains(mark.peerID) else { return item.metrics.overallScore }
            return max(0, item.metrics.overallScore - mark.penalty)
        }
        evaluatedMembers.sort {
            if cleanIDs.contains($0.asset.id) != cleanIDs.contains($1.asset.id) { return cleanIDs.contains($0.asset.id) }
            return score($0) == score($1) ? $0.asset.id.uuidString < $1.asset.id.uuidString : score($0) > score($1)
        }

        let best = evaluatedMembers[0]
        var winnerIndex = 0

        for i in 1..<evaluatedMembers.count {
            let candidate = evaluatedMembers[i]
            let diff = score(best) - score(candidate)
            if cleanIDs.contains(best.asset.id) && !cleanIDs.contains(candidate.asset.id) { continue }
            if diff <= prefs.qualityEquivalenceThreshold {
                if shouldPrefer(candidate: candidate, over: evaluatedMembers[winnerIndex], prefs: prefs) {
                    winnerIndex = i
                }
            } else { break }
        }

        var newMembers: [ClusterMember] = []
        for (i, eval) in evaluatedMembers.enumerated() {
            var newMember = eval.member
            newMember.isRecommendedKeep = (i == winnerIndex)
            newMember.qualityScore = score(eval)
            newMember.fileSize = eval.asset.fileIdentity.fileSize
            newMembers.append(newMember)
        }

        return DuplicateCluster(
            id: cluster.id,
            members: newMembers,
            representativeMatchType: cluster.representativeMatchType,
            overallSimilarity: cluster.overallSimilarity,
            createdAt: cluster.createdAt,
            updatedAt: Date()
        )
    }

    private func shouldPrefer(
        candidate: (member: ClusterMember, asset: VideoAsset, metrics: QualityMetrics),
        over currentBest: (member: ClusterMember, asset: VideoAsset, metrics: QualityMetrics),
        prefs: Preferences
    ) -> Bool {
        if candidate.metrics.upscaleSuspicion != currentBest.metrics.upscaleSuspicion {
            return candidate.metrics.upscaleSuspicion == .none
        }
        if prefs.preferSpaceSaving {
            let sizeC = candidate.asset.fileIdentity.fileSize
            let sizeB = currentBest.asset.fileIdentity.fileSize
            if sizeC > 0 && sizeB > 0 && Double(min(sizeC, sizeB)) < Double(max(sizeC, sizeB)) * 0.90 {
                return sizeC < sizeB
            }
        }
        if prefs.preferAppleNative {
            let isNativeC = isAppleNative(candidate.asset.metadata?.container)
            let isNativeB = isAppleNative(currentBest.asset.metadata?.container)
            if isNativeC != isNativeB { return isNativeC }
        }
        return candidate.asset.fileIdentity.modificationDate < currentBest.asset.fileIdentity.modificationDate
    }

    private func isAppleNative(_ container: String?) -> Bool {
        guard let ext = container?.lowercased() else { return false }
        return ext.contains("mp4") || ext.contains("mov") || ext.contains("m4v")
    }
}
