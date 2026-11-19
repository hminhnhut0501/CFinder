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
        public var preferSpaceSaving: Bool = false // Quality First: Never sacrifice quality for file size
        public var qualityEquivalenceThreshold: Float = 3.0 // Tight equivalence threshold

        public init(preferAppleNative: Bool = true, preferSpaceSaving: Bool = false, qualityEquivalenceThreshold: Float = 3.0) {
            self.preferAppleNative = preferAppleNative
            self.preferSpaceSaving = preferSpaceSaving
            self.qualityEquivalenceThreshold = qualityEquivalenceThreshold
        }
    }

    private func pixelCount(_ item: (member: ClusterMember, asset: VideoAsset, metrics: QualityMetrics)) -> Int {
        let vs = item.asset.metadata?.videoStream
        let w = max(vs?.displayWidth ?? 0, vs?.width ?? 0)
        let h = max(vs?.displayHeight ?? 0, vs?.height ?? 0)
        return w * h
    }

    private func effectiveBitrate(_ item: (member: ClusterMember, asset: VideoAsset, metrics: QualityMetrics)) -> Int64 {
        if let b = item.asset.metadata?.videoStream?.bitrate, b > 0 { return b }
        let dur = item.asset.metadata?.durationSeconds ?? 0
        if dur > 0, item.asset.fileIdentity.fileSize > 0 {
            return Int64(Double(item.asset.fileIdentity.fileSize * 8) / dur)
        }
        return 0
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

        // TIERED SORTING:
        // Tier 1: Dominant Resolution Check (e.g. 1080p vs 720p, 4K vs 1080p)
        // Tier 2: Composite Quality Score (Resolution + Resolution-Aware Bitrate + Codec)
        // Tier 3: Effective Bitrate (Higher Bitrate wins when resolutions are identical)
        evaluatedMembers.sort { a, b in
            // Clean watermark priority
            if cleanIDs.contains(a.asset.id) != cleanIDs.contains(b.asset.id) {
                return cleanIDs.contains(a.asset.id)
            }
            
            let pixA = pixelCount(a)
            let pixB = pixelCount(b)
            let durA = a.asset.metadata?.durationSeconds ?? 0
            let durB = b.asset.metadata?.durationSeconds ?? 0
            
            // Tier 1: Dominant Resolution Check
            if pixA > 0 && pixB > 0 && Double(max(pixA, pixB)) >= Double(min(pixA, pixB)) * 1.15 {
                if pixA > pixB && durA >= longestDuration * 0.90 {
                    return true
                }
                if pixB > pixA && durB >= longestDuration * 0.90 {
                    return false
                }
            }
            
            // Tier 2: Composite Quality Score
            let scoreA = score(a)
            let scoreB = score(b)
            if abs(scoreA - scoreB) > 0.5 {
                return scoreA > scoreB
            }
            
            // Tier 3: Effective Bitrate (Higher Bitrate Wins!)
            let bA = effectiveBitrate(a)
            let bB = effectiveBitrate(b)
            if bA != bB {
                return bA > bB
            }
            
            return a.asset.id.uuidString < b.asset.id.uuidString
        }

        let best = evaluatedMembers[0]
        var winnerIndex = 0

        for i in 1..<evaluatedMembers.count {
            let candidate = evaluatedMembers[i]
            let diff = score(best) - score(candidate)
            if cleanIDs.contains(best.asset.id) && !cleanIDs.contains(candidate.asset.id) { continue }
            
            // If best has significantly higher resolution, candidate can NEVER overturn it!
            let pixBest = pixelCount(best)
            let pixCandidate = pixelCount(candidate)
            if pixBest > 0 && pixCandidate > 0 && Double(pixBest) >= Double(pixCandidate) * 1.15 {
                continue
            }
            
            // If best has higher bitrate at same resolution, candidate can NEVER overturn it!
            let bBest = effectiveBitrate(best)
            let bCandidate = effectiveBitrate(candidate)
            if bBest > 0 && bCandidate > 0 && Double(bBest) >= Double(bCandidate) * 1.20 {
                continue
            }
            
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
        
        let pixC = pixelCount(candidate)
        let pixB = pixelCount(currentBest)
        
        // NEVER prefer candidate if it has lower resolution
        if pixB > 0 && pixC > 0 && Double(pixB) >= Double(pixC) * 1.15 {
            return false
        }
        if pixC > 0 && pixB > 0 && Double(pixC) >= Double(pixB) * 1.15 {
            return true
        }
        
        let bC = effectiveBitrate(candidate)
        let bB = effectiveBitrate(currentBest)
        
        // NEVER prefer candidate if it has significantly lower bitrate!
        if bB > 0 && bC > 0 && Double(bB) >= Double(bC) * 1.20 {
            return false
        }
        if bC > 0 && bB > 0 && Double(bC) >= Double(bB) * 1.20 {
            return true
        }
        
        // Space saving ONLY if resolution AND bitrate are essentially identical (within 15%)
        if prefs.preferSpaceSaving {
            let isSameRes = abs(pixC - pixB) <= Int(Double(max(pixC, pixB, 1)) * 0.05)
            let isSameBitrate = abs(bC - bB) <= Int64(Double(max(bC, bB, 1)) * 0.15)
            if isSameRes && isSameBitrate {
                let sizeC = candidate.asset.fileIdentity.fileSize
                let sizeB = currentBest.asset.fileIdentity.fileSize
                if sizeC > 0 && sizeB > 0 && Double(min(sizeC, sizeB)) < Double(max(sizeC, sizeB)) * 0.90 {
                    return sizeC < sizeB
                }
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
