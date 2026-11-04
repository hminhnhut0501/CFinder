import Foundation

/// Protocol defining storage operations for VideoTwin scanning sessions.
/// Allows swapping between in-memory session cache and persistent SQLite storage.
public protocol VideoTwinStorage: Sendable {
    func fetchAsset(byIdentity identity: FileIdentity, includingModified: Bool) async throws -> VideoAsset?
    func loadAnalysis(id: UUID) async throws -> VideoAsset?
    func cachedHashes(for assets: [VideoAsset]) async throws -> [UUID: ExactDuplicateEngine.CachedHash]
    func saveAnalysis(_ asset: VideoAsset) async throws
    func recordHashes(assetID: UUID, quick: String?, full: String?) async throws
    func pruneAnalysis(in roots: [URL], keeping: Set<UUID>) async throws
    func saveResults(clusters: [DuplicateCluster], matches: [MatchResult]) async throws
}
