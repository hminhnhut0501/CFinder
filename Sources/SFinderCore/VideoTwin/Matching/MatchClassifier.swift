import Foundation
import OSLog

/// Rule-based match classifier.
///
/// Input: Multi-dimensional scores (visual, timeline, audio, duration, metadata, coverage)
/// Output: MatchType + MatchConfidence
///
/// Design (spec §26, §27):
///   - No ML in v1. Pure rule-based.
///   - All thresholds from SimilarityConfiguration, never hardcoded.
///   - Architecture allows replacing with learned classifier later.
///   - Separates "similarity" from "confidence" (spec §27).
public struct MatchClassifier: Sendable {
    let config: SimilarityConfiguration

    // MARK: - Input

    struct ScoreInput: Sendable {
        let visualScore: Float
        let timelineScore: Float
        let audioScore: Float?
        let durationScore: Float
        let coverageA: Float
        let coverageB: Float
        let alignment: AlignmentResult?

        // Metadata signals
        let codecA: String?
        let codecB: String?
        let resolutionA: (w: Int, h: Int)?
        let resolutionB: (w: Int, h: Int)?
        let fpsA: Double?
        let fpsB: Double?
        let matchedSamples: Int
        let totalSamples: Int
    }

    // MARK: - Classification

    func classify(scores: ScoreInput) -> (type: MatchType, confidence: MatchConfidence) {
        let visual = scores.visualScore
        let coverage = min(scores.coverageA, scores.coverageB)
        let maxCoverage = max(scores.coverageA, scores.coverageB)

        // ── Not a match ──────────────────────────────────────────────
        if visual < config.possibleThreshold {
            return (.different, .certain)
        }

        // ── Confidence calculation ────────────────────────────────────
        let confidence = calculateConfidence(scores: scores)

        // ── Exact (100% visual similarity handled upstream via hash) ──
        // Note: exact duplicates are caught before reaching classifier.
        // This handles "near-exact" with 99%+ visual score.
        if visual >= 0.99 && coverage > 0.95 {
            return (.nearDuplicate, confidence)
        }

        // ── Contained clip ─────────────────────────────────────────────
        // One video is a segment of the other:
        //   - High coverage of shorter (coverageA or coverageB near 1.0)
        //   - Low coverage of longer
        //   - High visual score on the overlapping segment
        if scores.coverageA > config.containedClipMinCoverage
            && scores.coverageB < 0.5
            && visual >= config.nearDuplicateThreshold {
            return (.containedClip, confidence)
        }
        if scores.coverageB > config.containedClipMinCoverage
            && scores.coverageA < 0.5
            && visual >= config.nearDuplicateThreshold {
            return (.containedClip, confidence)
        }

        // ── Trimmed variant ───────────────────────────────────────────
        // Both videos have high coverage of each other but one has added intro/outro
        if visual >= config.nearDuplicateThreshold
            && maxCoverage >= 0.85
            && coverage < 0.95
            && scores.alignment != nil {
            return (.trimmed, confidence)
        }

        // ── Resolution variant ────────────────────────────────────────
        if visual >= config.nearDuplicateThreshold,
           let rA = scores.resolutionA,
           let rB = scores.resolutionB {
            let pixelsA = rA.w * rA.h
            let pixelsB = rB.w * rB.h
            let ratio = Double(min(pixelsA, pixelsB)) / Double(max(pixelsA, pixelsB))
            if ratio < 0.75 {  // significantly different resolution (e.g., 1080p vs 4K)
                return (.resolutionVariant, confidence)
            }
        }

        // ── FPS variant ───────────────────────────────────────────────
        if visual >= config.nearDuplicateThreshold,
           let fA = scores.fpsA,
           let fB = scores.fpsB,
           fA > 0, fB > 0 {
            let fpsRatio = min(fA, fB) / max(fA, fB)
            if fpsRatio < 0.70 {  // e.g., 24 vs 60 FPS
                return (.fpsVariant, confidence)
            }
        }

        // ── Re-encoded ────────────────────────────────────────────────
        if visual >= config.nearDuplicateThreshold {
            // Different codec or container but same content
            if let cA = scores.codecA, let cB = scores.codecB,
               normalizeCodec(cA) != normalizeCodec(cB) {
                return (.reencoded, confidence)
            }
            // Same codec, high similarity but not exact → re-encode (different bitrate/settings)
            return (.reencoded, confidence)
        }

        // ── Near duplicate ────────────────────────────────────────────
        if visual >= config.nearDuplicateThreshold * 0.95 {
            return (.nearDuplicate, confidence)
        }

        // ── Possible match ────────────────────────────────────────────
        if visual >= config.possibleThreshold {
            return (.possibleMatch, .low)
        }

        return (.different, .certain)
    }

    // MARK: - Confidence

    private func calculateConfidence(scores: ScoreInput) -> MatchConfidence {
        let visual = scores.visualScore
        let sampleRatio = scores.totalSamples > 0
            ? Float(scores.matchedSamples) / Float(scores.totalSamples)
            : 0

        // Start with visual score contribution
        var score: Float = visual * 0.5

        // Sample coverage: more matched samples → higher confidence
        score += sampleRatio * 0.3

        // Timeline alignment adds confidence
        if let alignment = scores.alignment {
            score += alignment.alignmentConfidence * 0.1
        }

        // Audio match adds confidence
        if let audio = scores.audioScore, audio > 0.7 {
            score += (audio - 0.7) * 0.1
        }

        // Minimum sample threshold (spec §27)
        guard scores.matchedSamples >= config.minimumAlignedSamples else {
            return .low
        }

        switch score {
        case 0.95...: return .certain
        case 0.88...: return .veryHigh
        case 0.78...: return .high
        case 0.65...: return .medium
        default:       return .low
        }
    }

    // MARK: - Helpers

    private func normalizeCodec(_ codec: String) -> String {
        // Map codec aliases to canonical names
        let lower = codec.lowercased()
        if lower.contains("h264") || lower.contains("avc1") || lower.contains("avc") { return "h264" }
        if lower.contains("hevc") || lower.contains("hvc1") || lower.contains("h265") { return "hevc" }
        if lower.contains("av1") || lower.contains("av01") { return "av1" }
        if lower.contains("vp9") { return "vp9" }
        if lower.contains("vp8") { return "vp8" }
        return lower
    }
}
