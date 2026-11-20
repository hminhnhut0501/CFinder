import Foundation
import CoreMedia
import OSLog

/// Thread-safe deduplicated cache for deep-level frame fingerprints within a scan session.
private actor DeepFingerprintCache {
    private var cache: [UUID: [FrameSample]] = [:]
    private var order: [UUID] = []
    private var inFlight: [UUID: Task<[FrameSample], Error>] = [:]
    private let maxCacheEntries = 64

    func fingerprints(for asset: VideoAsset) async throws -> [FrameSample] {
        if let cached = cache[asset.id] {
            return cached
        }
        if let existingTask = inFlight[asset.id] {
            return try await existingTask.value
        }
        let task = Task<[FrameSample], Error> {
            try await VideoAnalyzer.fingerprints(asset, level: .deep)
        }
        inFlight[asset.id] = task
        do {
            let result = try await task.value
            cache[asset.id] = result
            order.append(asset.id)
            while order.count > maxCacheEntries {
                let evictID = order.removeFirst()
                cache.removeValue(forKey: evictID)
            }
            inFlight[asset.id] = nil
            return result
        } catch {
            inFlight[asset.id] = nil
            throw error
        }
    }
}

/// Full visual matching engine for a candidate pair.
///
/// Pipeline (spec §19, §28):
///   1. Coarse: compare full + center-safe dHash fingerprints → early reject if too low
///   2. Medium: compare full + center-safe + 2x2 grid pHash fingerprints (overlay/logo robust)
///   3. Timeline alignment (uses cached deep fingerprints for different durations)
///   4. Classification via MatchClassifier
///
/// All thresholds from SimilarityConfiguration.
public final class MatchEngine: Sendable {
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "matcher")
    private let aligner: TimelineAligner
    private let classifier: MatchClassifier
    private let config: SimilarityConfiguration
    private let deepCache = DeepFingerprintCache()

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
        let minInfo = min(3, config.minimumAlignedSamples)
        guard informativeCount(assetA) >= minInfo,
              informativeCount(assetB) >= minInfo else { return nil }
        let id = UUID()
        let now = Date()
        let version = "visual-v4"

        let durationA = assetA.metadata?.durationSeconds ?? 0
        let durationB = assetB.metadata?.durationSeconds ?? 0
        let ratio = min(durationA, durationB) / max(durationA, durationB, 0.001)

        // Stage 1: Coarse dHash (full + center-safe) — early reject only for equal-duration pairs
        var (coarseScore, coarseFrameScores) = coarseDHashScore(assetA: assetA, assetB: assetB)
        if ratio < Double(config.durationRatioMin) {
            // For split segments / skewed durations (Part 1, Part 2, Part 3...),
            // sequential frame-by-frame comparison is invalid because Part 2 starts mid-movie.
            // Check cross-frame similarity instead.
            let crossScore = crossFrameDHashScore(assetA: assetA, assetB: assetB)
            coarseScore = max(coarseScore, crossScore)
        } else if let _ = earlyReject(frameScores: coarseFrameScores) {
            logger.debug("Early reject: \(assetA.path.lastPathComponent) vs \(assetB.path.lastPathComponent), coarse=\(coarseScore)")
            return nil
        }

        // Stage 2: pHash comparison (full + center-safe + 2x2 grid top-3)
        let pHashScore = pHashSimilarity(assetA: assetA, assetB: assetB)

        // Stage 3: Combined visual score (weighted)
        var visualScore = coarseScore * 0.4 + pHashScore * 0.6

        // Stage 4: Timeline alignment (with cached deep sampling if duration differs)
        if ratio < Double(config.durationRatioMin),
           FileManager.default.fileExists(atPath: assetA.path.path),
           FileManager.default.fileExists(atPath: assetB.path.path) {
            // Skip deep 32-frame decode if coarse dHash indicates completely unrelated content
            guard coarseScore >= config.coarseRejectThreshold else { return nil }
            do {
                assetA.fingerprints = try await deepCache.fingerprints(for: assetA)
                assetB.fingerprints = try await deepCache.fingerprints(for: assetB)
            } catch { return nil }
        }

        var alignment = await aligner.align(
            framesA: dHashAndCenterTimestamps(assetA),
            framesB: dHashAndCenterTimestamps(assetB),
            durationA: durationA,
            durationB: durationB
        )

        var isCroppedVariant = false
        if let align = alignment {
            let (alignedScore, isCrop) = alignedVisualScore(assetA, assetB, offset: align.offsetSeconds)
            if isCrop { isCroppedVariant = true }
            visualScore = ratio >= Double(config.durationRatioMin) ? max(visualScore, alignedScore) : alignedScore

            if ratio < Double(config.durationRatioMin), FileManager.default.fileExists(atPath: assetA.path.path) {
                let start = max(0, -align.offsetSeconds)
                let end = min(durationA, durationB - align.offsetSeconds)
                guard end > start else { return nil }
                let times = FrameSampler.mediumPositions.map { start + $0 * (end - start) }
                do {
                    assetA.fingerprints = try await VideoAnalyzer.fingerprints(assetA, level: .medium, times: times)
                    assetB.fingerprints = try await VideoAnalyzer.fingerprints(assetB, level: .medium, times: times.map { $0 + align.offsetSeconds })
                } catch { return nil }
                let (refinedScore, isRefinedCrop) = alignedVisualScore(assetA, assetB, offset: align.offsetSeconds)
                if isRefinedCrop { isCroppedVariant = true }
                visualScore = refinedScore
                // Allow down to 0.78 for partial/split clips or clips with logo/text overlays/crop
                guard visualScore >= 0.78 else { return nil }
                let matched = min(assetA.fingerprints.count, assetB.fingerprints.count)
                alignment = AlignmentResult(
                    offsetSeconds: align.offsetSeconds,
                    alignmentConfidence: min(align.alignmentConfidence, visualScore),
                    matchedFrames: matched,
                    unmatchedFrames: 0,
                    coverageA: Float((end - start) / durationA),
                    coverageB: Float((end - start) / durationB)
                )
            }
        } else if ratio < Double(config.durationRatioMin) {
            // If duration differs and no timeline alignment could be established, avoid false positives
            return nil
        }

        // Cross-orientation detection (16:9 vs 9:16)
        if let ma = assetA.metadata?.videoStream, let mb = assetB.metadata?.videoStream {
            let isCross = (ma.aspectRatio >= 1.2 && mb.aspectRatio <= 0.95) || (mb.aspectRatio >= 1.2 && ma.aspectRatio <= 0.95)
            if isCross && visualScore >= 0.78 {
                isCroppedVariant = true
            }
        }

        let timelineScore: Float = alignment?.alignmentConfidence ?? 0

        // Duration score
        let durationScore: Float
        if durationA > 0 && durationB > 0 {
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
            audioScore: nil,  // TODO: Phase 3 audio
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
            isCroppedVariant: isCroppedVariant,
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

    // MARK: - Overlay-Robust Frame Similarity

    private func informativeCount(_ asset: VideoAsset) -> Int {
        asset.fingerprints.filter { sample in
            guard let fp = sample.visualFingerprint, let d = fp.dHash, let p = fp.pHash, p.count == 64 else { return false }
            let ones = p.filter { $0 == 1 }.count
            return (d != 0 && d != UInt64.max) || (ones > 1 && ones < 63)
        }.count
    }

    private func frameDHashSimilarity(_ fpA: VisualFingerprint, _ fpB: VisualFingerprint) -> Float {
        var best: Float = 0
        if let da = fpA.dHash, let db = fpB.dHash {
            best = max(best, DHasher.similarity(da, db))
        }
        if let ca = fpA.centerDHash, let cb = fpB.centerDHash {
            best = max(best, DHasher.similarity(ca, cb))
        }
        // Cross Crop & Zoom check (Full vs Zoom, Center vs Zoom)
        if let za = fpA.zoomDHash, let db = fpB.dHash {
            best = max(best, DHasher.similarity(za, db))
        }
        if let da = fpA.dHash, let zb = fpB.zoomDHash {
            best = max(best, DHasher.similarity(da, zb))
        }
        if let za = fpA.zoomDHash, let cb = fpB.centerDHash {
            best = max(best, DHasher.similarity(za, cb))
        }
        if let ca = fpA.centerDHash, let zb = fpB.zoomDHash {
            best = max(best, DHasher.similarity(ca, zb))
        }
        return best
    }

    private func framePHashSimilarity(_ fpA: VisualFingerprint, _ fpB: VisualFingerprint) -> Float {
        var best: Float = 0
        if let pa = fpA.pHash, let pb = fpB.pHash {
            best = max(best, PHasher.similarity(pa, pb))
        }
        if let ca = fpA.centerPHash, let cb = fpB.centerPHash {
            best = max(best, PHasher.similarity(ca, cb))
        }
        // Cross Crop & Zoom check for pHash
        if let za = fpA.zoomPHash, let pb = fpB.pHash {
            best = max(best, PHasher.similarity(za, pb))
        }
        if let pa = fpA.pHash, let zb = fpB.zoomPHash {
            best = max(best, PHasher.similarity(pa, zb))
        }
        if let za = fpA.zoomPHash, let cb = fpB.centerPHash {
            best = max(best, PHasher.similarity(za, cb))
        }
        if let ca = fpA.centerPHash, let zb = fpB.zoomPHash {
            best = max(best, PHasher.similarity(ca, zb))
        }
        if let ga = fpA.gridPHashes, let gb = fpB.gridPHashes, ga.count == 4, gb.count == 4 {
            var qScores = [Float](repeating: 0, count: 4)
            for i in 0..<4 {
                qScores[i] = PHasher.similarity(ga[i], gb[i])
            }
            qScores.sort(by: >)
            // Average top 3 out of 4 quadrants to resist corner logos or bottom/top text banners
            let top3Avg = (qScores[0] + qScores[1] + qScores[2]) / 3.0
            best = max(best, top3Avg)
        }
        return best
    }

    private func frameCombinedSimilarity(_ a: FrameSample, _ b: FrameSample) -> (score: Float, isCropped: Bool) {
        guard let fpA = a.visualFingerprint, let fpB = b.visualFingerprint else { return (0, false) }
        let fullD = (fpA.dHash != nil && fpB.dHash != nil) ? DHasher.similarity(fpA.dHash!, fpB.dHash!) : 0
        let fullP = (fpA.pHash != nil && fpB.pHash != nil) ? PHasher.similarity(fpA.pHash!, fpB.pHash!) : 0
        let fullScore = fullD * 0.4 + fullP * 0.6

        let centerD = (fpA.centerDHash != nil && fpB.centerDHash != nil) ? DHasher.similarity(fpA.centerDHash!, fpB.centerDHash!) : 0
        let centerP = (fpA.centerPHash != nil && fpB.centerPHash != nil) ? PHasher.similarity(fpA.centerPHash!, fpB.centerPHash!) : 0
        let centerScore = (fpA.centerDHash != nil && fpB.centerDHash != nil) ? (centerD * 0.4 + centerP * 0.6) : 0

        let gridP = framePHashSimilarity(fpA, fpB)
        let standardBest = max(fullScore, centerScore, gridP)

        // Cross Zoom & Crop matching
        var zoomBest: Float = 0
        if let za = fpA.zoomDHash, let db = fpB.dHash, let zp = fpA.zoomPHash, let pb = fpB.pHash {
            let s = DHasher.similarity(za, db) * 0.4 + PHasher.similarity(zp, pb) * 0.6
            zoomBest = max(zoomBest, s)
        }
        if let da = fpA.dHash, let zb = fpB.zoomDHash, let pa = fpA.pHash, let zp = fpB.zoomPHash {
            let s = DHasher.similarity(da, zb) * 0.4 + PHasher.similarity(pa, zp) * 0.6
            zoomBest = max(zoomBest, s)
        }
        if let za = fpA.zoomDHash, let cb = fpB.centerDHash, let zp = fpA.zoomPHash, let cp = fpB.centerPHash {
            let s = DHasher.similarity(za, cb) * 0.4 + PHasher.similarity(zp, cp) * 0.6
            zoomBest = max(zoomBest, s)
        }
        if let ca = fpA.centerDHash, let zb = fpB.zoomDHash, let cp = fpA.centerPHash, let zp = fpB.zoomPHash {
            let s = DHasher.similarity(ca, zb) * 0.4 + PHasher.similarity(cp, zp) * 0.6
            zoomBest = max(zoomBest, s)
        }

        if zoomBest > standardBest && zoomBest >= 0.78 {
            return (zoomBest, true)
        }
        return (standardBest, false)
    }

    private func alignedVisualScore(_ a: VideoAsset, _ b: VideoAsset, offset: Double) -> (score: Float, isCropped: Bool) {
        var scores: [Float] = []
        var croppedCount = 0
        for sample in a.fingerprints {
            guard let other = b.fingerprints.min(by: { abs($0.timestampSeconds - sample.timestampSeconds - offset) < abs($1.timestampSeconds - sample.timestampSeconds - offset) }),
                  abs(other.timestampSeconds - sample.timestampSeconds - offset) <= config.alignmentToleranceSeconds else { continue }
            let res = frameCombinedSimilarity(sample, other)
            scores.append(res.score)
            if res.isCropped { croppedCount += 1 }
        }
        let minRequired = min(3, config.minimumAlignedSamples)
        guard scores.count >= minRequired else { return (0, false) }
        let avg = scores.reduce(0, +) / Float(scores.count)
        let isCrop = croppedCount >= max(1, scores.count / 3)
        return (avg, isCrop)
    }

    // MARK: - Score computations

    private func coarseDHashScore(assetA: VideoAsset, assetB: VideoAsset) -> (Float, [Float]) {
        let fpsA = assetA.fingerprints.compactMap { $0.visualFingerprint }
        let fpsB = assetB.fingerprints.compactMap { $0.visualFingerprint }

        guard !fpsA.isEmpty, !fpsB.isEmpty else { return (0, []) }

        var frameScores: [Float] = []
        let count = min(fpsA.count, fpsB.count)
        frameScores.reserveCapacity(count)
        for i in 0..<count {
            frameScores.append(frameDHashSimilarity(fpsA[i], fpsB[i]))
        }

        let avg = frameScores.isEmpty ? 0 : frameScores.reduce(0, +) / Float(frameScores.count)
        return (avg, frameScores)
    }

    private func crossFrameDHashScore(assetA: VideoAsset, assetB: VideoAsset) -> Float {
        let fpsA = assetA.fingerprints.compactMap { $0.visualFingerprint }
        let fpsB = assetB.fingerprints.compactMap { $0.visualFingerprint }
        guard !fpsA.isEmpty, !fpsB.isEmpty else { return 0 }

        var maxSim: Float = 0
        for a in fpsA {
            for b in fpsB {
                let sim = frameDHashSimilarity(a, b)
                if sim > maxSim { maxSim = sim }
            }
        }
        return maxSim
    }

    private func earlyReject(frameScores: [Float]) -> Bool? {
        guard frameScores.count >= config.earlyRejectFrameCount else { return nil }
        let firstN = Array(frameScores.prefix(config.earlyRejectFrameCount))
        if firstN.allSatisfy({ $0 < config.earlyRejectFrameThreshold }) {
            return true
        }
        return nil
    }

    private func pHashSimilarity(assetA: VideoAsset, assetB: VideoAsset) -> Float {
        let fpsA = assetA.fingerprints.compactMap { $0.visualFingerprint }
        let fpsB = assetB.fingerprints.compactMap { $0.visualFingerprint }

        guard !fpsA.isEmpty, !fpsB.isEmpty else { return 0 }

        var total: Float = 0
        let count = min(fpsA.count, fpsB.count)
        for i in 0..<count {
            total += framePHashSimilarity(fpsA[i], fpsB[i])
        }
        return count > 0 ? total / Float(count) : 0
    }

    private func dHashAndCenterTimestamps(_ asset: VideoAsset) -> [(timestamp: Double, dHash: UInt64, centerDHash: UInt64?, zoomDHash: UInt64?)] {
        asset.fingerprints.compactMap { sample in
            guard let hash = sample.visualFingerprint?.dHash else { return nil }
            return (sample.timestampSeconds, hash, sample.visualFingerprint?.centerDHash, sample.visualFingerprint?.zoomDHash)
        }
    }

    private func metadataSimilarity(assetA: VideoAsset, assetB: VideoAsset) -> Float {
        guard let metaA = assetA.metadata?.videoStream,
              let metaB = assetB.metadata?.videoStream else { return 0 }

        var score: Float = 0
        var factors = 0

        let arA = metaA.aspectRatio
        let arB = metaB.aspectRatio
        if arA > 0 && arB > 0 {
            let diff = abs(arA - arB) / max(arA, arB)
            score += Float(1.0 - min(1.0, diff * 2))
            factors += 1
        }

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
