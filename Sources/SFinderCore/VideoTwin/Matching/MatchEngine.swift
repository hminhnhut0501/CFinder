import Foundation
import CoreMedia
import OSLog

/// Full visual matching engine for a candidate pair.
///
/// Pipeline (spec §19, §28):
///   1. Coarse: compare dHash fingerprints → early reject if too low
///   2. Medium: compare pHash fingerprints
///   3. Fine: Vision FeaturePrint (only for promising candidates)
///   4. Timeline alignment (if duration close or offset suspected)
///   5. Classification via MatchClassifier
///
/// All thresholds from SimilarityConfiguration.
public actor MatchEngine {
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "matcher")
    private let aligner: TimelineAligner
    private let classifier: MatchClassifier
    private let config: SimilarityConfiguration

    public init(config: SimilarityConfiguration = .default) {
        self.aligner = TimelineAligner(config: config)
        self.classifier = MatchClassifier(config: config)
        self.config = config
    }

    // MARK: - Public API

    /// Match two assets using all available fingerprints.
    /// Returns nil if early-rejected (definitely not a match).
    func match(assetA inputA: VideoAsset, assetB inputB: VideoAsset) async -> MatchResult? {
        var assetA = inputA, assetB = inputB
        guard informativeCount(assetA) >= config.minimumAlignedSamples,
              informativeCount(assetB) >= config.minimumAlignedSamples else { return nil }
        let id = UUID()
        let now = Date()
        let version = "visual-v3"

        // Stage 1: Coarse dHash — early reject (spec §28)
        let (coarseScore, coarseFrameScores) = coarseDHashScore(assetA: assetA, assetB: assetB)
        if let reject = earlyReject(frameScores: coarseFrameScores), assetA.metadata?.durationSeconds == assetB.metadata?.durationSeconds {
            logger.debug("Early reject: \(assetA.path.lastPathComponent) vs \(assetB.path.lastPathComponent), coarse=\(coarseScore)")
            _ = reject
            return nil
        }

        // Stage 2: pHash comparison
        let pHashScore = pHashSimilarity(assetA: assetA, assetB: assetB)

        // Stage 3: Combined visual score (weighted)
        var visualScore = coarseScore * 0.4 + pHashScore * 0.6

        // Stage 4: Timeline alignment
        let framesA = dHashTimestamps(assetA)
        let framesB = dHashTimestamps(assetB)
        let durationA = assetA.metadata?.durationSeconds ?? 0
        let durationB = assetB.metadata?.durationSeconds ?? 0

        let ratio = min(durationA, durationB) / max(durationA, durationB, 0.001)
        if ratio < Double(config.durationRatioMin), FileManager.default.fileExists(atPath: assetA.path.path), FileManager.default.fileExists(atPath: assetB.path.path) {
            do {
                assetA.fingerprints = try await VideoAnalyzer.fingerprints(assetA, level: .deep)
                assetB.fingerprints = try await VideoAnalyzer.fingerprints(assetB, level: .deep)
            } catch { return nil }
        }
        var alignment = await aligner.align(
            framesA: ratio < Double(config.durationRatioMin) ? dHashTimestamps(assetA) : framesA,
            framesB: ratio < Double(config.durationRatioMin) ? dHashTimestamps(assetB) : framesB,
            durationA: durationA,
            durationB: durationB
        )

        if let align = alignment {
            visualScore = alignedVisualScore(assetA, assetB, offset: align.offsetSeconds)
            if ratio < Double(config.durationRatioMin), FileManager.default.fileExists(atPath: assetA.path.path) {
                let start = max(0, -align.offsetSeconds)
                let end = min(durationA, durationB - align.offsetSeconds)
                guard end > start else { return nil }
                let times = FrameSampler.mediumPositions.map { start + $0 * (end - start) }
                do {
                    assetA.fingerprints = try await VideoAnalyzer.fingerprints(assetA, level: .medium, times: times)
                    assetB.fingerprints = try await VideoAnalyzer.fingerprints(assetB, level: .medium, times: times.map { $0 + align.offsetSeconds })
                } catch { return nil }
                visualScore = alignedVisualScore(assetA, assetB, offset: align.offsetSeconds)
                guard visualScore >= config.nearDuplicateThreshold else { return nil }
                let matched = min(assetA.fingerprints.count, assetB.fingerprints.count)
                alignment = AlignmentResult(offsetSeconds: align.offsetSeconds, alignmentConfidence: min(align.alignmentConfidence, visualScore), matchedFrames: matched, unmatchedFrames: 0, coverageA: Float((end - start) / durationA), coverageB: Float((end - start) / durationB))
            }
        }
        let timelineScore: Float = alignment?.alignmentConfidence ?? 0

        // Duration score
        let durationScore: Float
        if durationA > 0 && durationB > 0 {
            let ratio = min(durationA, durationB) / max(durationA, durationB)
            durationScore = Float(ratio)
        } else {
            durationScore = 0
        }

        // Coverage
        let coverageA = alignment?.coverageA ?? 1.0
        let coverageB = alignment?.coverageB ?? 1.0

        // Count matched samples
        let matchedSamples = alignment?.matchedFrames ?? Int(Float(assetA.fingerprints.count) * visualScore)
        let totalSamples = max(assetA.fingerprints.count, assetB.fingerprints.count)

        // Metadata score (codec, resolution similarity)
        let metadataScore = metadataSimilarity(assetA: assetA, assetB: assetB)

        // Classification
        let input = MatchClassifier.ScoreInput(
            visualScore: visualScore,
            timelineScore: timelineScore,
            audioScore: nil,  // TODO: Phase 4 audio
            durationScore: durationScore,
            coverageA: coverageA,
            coverageB: coverageB,
            alignment: alignment,
            codecA: assetA.metadata?.videoStream?.codec,
            codecB: assetB.metadata?.videoStream?.codec,
            resolutionA: assetA.metadata?.videoStream.map { ($0.displayWidth, $0.displayHeight) },
            resolutionB: assetB.metadata?.videoStream.map { ($0.displayWidth, $0.displayHeight) },
            fpsA: assetA.metadata?.videoStream?.nominalFPS,
            fpsB: assetB.metadata?.videoStream?.nominalFPS,
            matchedSamples: matchedSamples,
            totalSamples: totalSamples
        )

        let (matchType, confidence) = classifier.classify(scores: input)

        // Final filter: discard DIFFERENT with high certainty
        guard matchType != .different else { return nil }

        return MatchResult(
            id: id,
            assetAID: assetA.id,
            assetBID: assetB.id,
            visualScore: visualScore,
            timelineScore: timelineScore,
            audioScore: nil,
            durationScore: durationScore,
            metadataScore: metadataScore,
            coverageScore: min(coverageA, coverageB),
            matchType: matchType,
            confidence: confidence,
            alignment: alignment,
            coverageA: coverageA,
            coverageB: coverageB,
            analysisVersion: version,
            analysedAt: now
        )
    }

    private func informativeCount(_ asset: VideoAsset) -> Int {
        asset.fingerprints.filter { sample in
            guard let fp = sample.visualFingerprint, let d = fp.dHash, let p = fp.pHash, p.count == 64 else { return false }
            let ones = p.filter { $0 == 1 }.count
            return (d != 0 && d != UInt64.max) || (ones > 1 && ones < 63)
        }.count
    }

    private func alignedVisualScore(_ a: VideoAsset, _ b: VideoAsset, offset: Double) -> Float {
        var scores: [Float] = []
        for sample in a.fingerprints {
            guard let other = b.fingerprints.min(by: { abs($0.timestampSeconds - sample.timestampSeconds - offset) < abs($1.timestampSeconds - sample.timestampSeconds - offset) }),
                  abs(other.timestampSeconds - sample.timestampSeconds - offset) <= config.alignmentToleranceSeconds,
                  let da = sample.visualFingerprint?.dHash, let db = other.visualFingerprint?.dHash,
                  let pa = sample.visualFingerprint?.pHash, let pb = other.visualFingerprint?.pHash else { continue }
            scores.append(DHasher.similarity(da, db) * 0.4 + PHasher.similarity(pa, pb) * 0.6)
        }
        return scores.count >= config.minimumAlignedSamples ? scores.reduce(0, +) / Float(scores.count) : 0
    }

    // MARK: - Score computations

    private func coarseDHashScore(assetA: VideoAsset, assetB: VideoAsset) -> (Float, [Float]) {
        let hashesA = assetA.fingerprints.compactMap { $0.visualFingerprint?.dHash }
        let hashesB = assetB.fingerprints.compactMap { $0.visualFingerprint?.dHash }

        guard !hashesA.isEmpty, !hashesB.isEmpty else { return (0, []) }

        // Compare corresponding frames (same position index)
        var frameScores: [Float] = []
        let count = min(hashesA.count, hashesB.count)
        for i in 0..<count {
            frameScores.append(DHasher.similarity(hashesA[i], hashesB[i]))
        }

        let avg = frameScores.isEmpty ? 0 : frameScores.reduce(0, +) / Float(frameScores.count)
        return (avg, frameScores)
    }

    private func earlyReject(frameScores: [Float]) -> Bool? {
        // Reject if first N frames are all below earlyRejectFrameThreshold
        guard frameScores.count >= config.earlyRejectFrameCount else { return nil }
        let firstN = Array(frameScores.prefix(config.earlyRejectFrameCount))
        if firstN.allSatisfy({ $0 < config.earlyRejectFrameThreshold }) {
            return true
        }
        return nil
    }

    private func pHashSimilarity(assetA: VideoAsset, assetB: VideoAsset) -> Float {
        let hashesA = assetA.fingerprints.compactMap { $0.visualFingerprint?.pHash }
        let hashesB = assetB.fingerprints.compactMap { $0.visualFingerprint?.pHash }

        guard !hashesA.isEmpty, !hashesB.isEmpty else { return 0 }

        var total: Float = 0
        let count = min(hashesA.count, hashesB.count)
        for i in 0..<count {
            total += PHasher.similarity(hashesA[i], hashesB[i])
        }
        return count > 0 ? total / Float(count) : 0
    }

    private func dHashTimestamps(_ asset: VideoAsset) -> [(timestamp: Double, dHash: UInt64)] {
        asset.fingerprints.compactMap { sample in
            guard let hash = sample.visualFingerprint?.dHash else { return nil }
            return (sample.timestampSeconds, hash)
        }
    }

    private func metadataSimilarity(assetA: VideoAsset, assetB: VideoAsset) -> Float {
        guard let metaA = assetA.metadata?.videoStream,
              let metaB = assetB.metadata?.videoStream else { return 0 }

        var score: Float = 0
        var factors = 0

        // Aspect ratio similarity
        let arA = metaA.aspectRatio
        let arB = metaB.aspectRatio
        if arA > 0 && arB > 0 {
            let diff = abs(arA - arB) / max(arA, arB)
            score += Float(1.0 - min(1.0, diff * 2))
            factors += 1
        }

        // Duration similarity
        let durA = CMTimeGetSeconds(metaA.duration)
        let durB = CMTimeGetSeconds(metaB.duration)
        if durA > 0 && durB > 0 {
            let ratio = min(durA, durB) / max(durA, durB)
            score += Float(ratio)
            factors += 1
        }

        return factors > 0 ? score / Float(factors) : 0
    }
}
