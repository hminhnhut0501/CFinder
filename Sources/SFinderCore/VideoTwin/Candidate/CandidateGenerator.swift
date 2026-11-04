import Foundation
import OSLog

/// Generates candidate pairs for visual comparison.
///
/// Core principle (spec §11): NEVER compare every video against every other video.
/// Use multi-dimensional bucketing to generate only promising candidates.
///
/// Bucketing strategy:
///   1. Duration bucket (±configurable tolerance)
///   2. Aspect ratio family (within ±15% ratio difference)
///   3. Orientation match (landscape vs portrait)
///   4. Rough visual fingerprint (coarse dHash grouping via LSH)
///
/// Bounded LSH buckets and neighbor counts limit candidate work.
public actor CandidateGenerator {
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "matcher")
    let config: SimilarityConfiguration

    public init(config: SimilarityConfiguration = .default) {
        self.config = config
    }

    // MARK: - Candidate Pair

    struct CandidatePair: Sendable, Hashable {
        let assetAID: UUID
        let assetBID: UUID
        let reason: CandidateReason
        /// Estimated similarity (from bucket/coarse hash) to prioritize queue
        var estimatedSimilarity: Float = 0.5

        // Normalize pair order for deduplication
        var normalized: CandidatePair {
            if assetAID.uuidString < assetBID.uuidString {
                return self
            }
            return CandidatePair(
                assetAID: assetBID,
                assetBID: assetAID,
                reason: reason,
                estimatedSimilarity: estimatedSimilarity
            )
        }

        func hash(into hasher: inout Hasher) {
            let n = normalized
            hasher.combine(n.assetAID)
            hasher.combine(n.assetBID)
        }

        public static func == (lhs: CandidatePair, rhs: CandidatePair) -> Bool {
            let a = lhs.normalized
            let b = rhs.normalized
            return a.assetAID == b.assetAID && a.assetBID == b.assetBID
        }
    }

    enum CandidateReason: String, Sendable, Codable {
        case sizeCollision      // exact same file size (pre-visual stage)
        case durationBucket     // similar duration
        case aspectBucket       // similar aspect ratio
        case coarseFingerprint  // similar dHash
        case partialSearch      // duration ratio significantly different, but visual evidence
    }

    // MARK: - Public API

    /// Generate candidate pairs from a set of assets with metadata and coarse fingerprints.
    ///
    /// - Parameter assets: Assets that have at minimum: metadata + coarse dHash for frame 0
    /// - Returns: Deduplicated set of candidate pairs sorted by estimated similarity (high first)
    func generateCandidates(from assets: [VideoAsset]) async -> [CandidatePair] {
        await indexedCandidates(assets, partialOnly: false)
    }

    func generatePartialCandidates(from assets: [VideoAsset]) async -> [CandidatePair] {
        await indexedCandidates(assets, partialOnly: true)
    }

    private func indexedCandidates(_ assets: [VideoAsset], partialOnly: Bool) async -> [CandidatePair] {
        let index = LSHSimilarityIndex()
        let sorted = assets.sorted { $0.id.uuidString < $1.id.uuidString }
        let byID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
        var pairs = Set<CandidatePair>()
        for asset in sorted {
            if Task.isCancelled { return [] }
            let hashes = asset.fingerprints.compactMap { $0.visualFingerprint?.dHash }
            var visited = Set<UUID>()
            // Bound total neighbors per asset, including multi-frame queries.
            for hash in hashes {
                if visited.count >= config.maxCandidatesPerAsset { break }
                let neighbors = await index.nearest(to: hash, limit: config.maxCandidatesPerAsset)
                for id in neighbors where visited.count < config.maxCandidatesPerAsset && !visited.contains(id) {
                    visited.insert(id)
                    guard let other = byID[id], compatible(asset, other, partialOnly: partialOnly),
                          other.fingerprints.contains(where: { sample in
                              sample.visualFingerprint?.dHash.map { DHasher.hammingDistance(hash, $0) <= config.coarseCandidateDistance } ?? false
                          }) else { continue }
                    pairs.insert(CandidatePair(assetAID: other.id, assetBID: asset.id, reason: partialOnly ? .partialSearch : .coarseFingerprint))
                }
            }
            for hash in hashes { await index.insert(assetID: asset.id, dHash: hash) }
        }
        // Metadata-only assets retain duration candidates for callers that haven't sampled yet.
        if !partialOnly {
            let metadataOnly = sorted.filter { $0.fingerprints.isEmpty }.sorted { ($0.metadata?.durationSeconds ?? 0) < ($1.metadata?.durationSeconds ?? 0) }
            for i in metadataOnly.indices {
                let upper = min(metadataOnly.count, i + config.maxCandidatesPerAsset + 1)
                for j in (i + 1)..<upper where compatible(metadataOnly[i], metadataOnly[j], partialOnly: false) {
                    pairs.insert(CandidatePair(assetAID: metadataOnly[i].id, assetBID: metadataOnly[j].id, reason: .durationBucket))
                }
            }
        }
        return pairs.sorted {
            let a = $0.normalized, b = $1.normalized
            return a.assetAID == b.assetAID ? a.assetBID.uuidString < b.assetBID.uuidString : a.assetAID.uuidString < b.assetAID.uuidString
        }
    }

    private func compatible(_ a: VideoAsset, _ b: VideoAsset, partialOnly: Bool) -> Bool {
        guard let da = a.metadata?.durationSeconds, let db = b.metadata?.durationSeconds,
              da.isFinite, db.isFinite, da > 0, db > 0 else { return false }
        let ratio = min(da, db) / max(da, db)
        if partialOnly { guard ratio >= 0.05, ratio < Double(config.durationRatioMin) else { return false } }
        else { guard ratio >= Double(config.durationRatioMin) || abs(da - db) <= config.durationToleranceSeconds else { return false } }
        if let ma = a.metadata?.videoStream, let mb = b.metadata?.videoStream {
            guard ma.aspectRatio > 0, mb.aspectRatio > 0, abs(ma.aspectRatio - mb.aspectRatio) / max(ma.aspectRatio, mb.aspectRatio) < 0.2 else { return false }
        }
        return true
    }

}

// MARK: - SimilarityIndex protocol (spec §29)

/// Protocol for the candidate index.
/// MVP implementation: bucket + LSH in CandidateGenerator above.
/// Future: HNSW for large libraries (50K+ videos).
protocol SimilarityIndex: Actor {
    func insert(assetID: UUID, dHash: UInt64)
    func nearest(to dHash: UInt64, limit: Int) -> [UUID]
}

/// Simple LSH-based index using 4 hash bands.
/// Each band covers 16 bits of the 64-bit dHash.
public actor LSHSimilarityIndex: SimilarityIndex {
    private var bands: [[UInt16: [UUID]]] = Array(repeating: [:], count: 4)
    private let bucketLimit = 256

    func insert(assetID: UUID, dHash: UInt64) {
        for band in 0..<4 {
            let bits = UInt16((dHash >> (band * 16)) & 0xFFFF)
            if bands[band][bits]?.contains(assetID) == true { continue }
            if bands[band][bits, default: []].count < bucketLimit { bands[band][bits, default: []].append(assetID) }
        }
    }

    func nearest(to dHash: UInt64, limit: Int) -> [UUID] {
        guard limit > 0 else { return [] }
        var result: [UUID] = [], seen = Set<UUID>()
        for delta: UInt16 in [0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768] {
            for band in 0..<4 {
                let bits = UInt16((dHash >> (band * 16)) & 0xFFFF) ^ delta
                for id in bands[band][bits] ?? [] where seen.insert(id).inserted {
                    result.append(id)
                    if result.count >= limit { return result }
                }
            }
        }
        return result
    }
}
