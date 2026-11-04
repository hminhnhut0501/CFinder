import Foundation

/// Fast, zero-overhead in-memory storage actor for on-demand duplicate scanning sessions.
/// All memory is released completely when this instance is deallocated upon closing the window.
public actor InMemoryVideoTwinStorage: VideoTwinStorage {
    private var assetsByID: [UUID: VideoAsset] = [:]
    private var assetsByIdentityKey: [String: VideoAsset] = [:]
    private var hashesByAssetID: [UUID: (quick: String?, full: String?)] = [:]
    private var savedClusters: [DuplicateCluster] = []
    private var savedMatches: [MatchResult] = []

    public init() {}

    private func identityKey(_ identity: FileIdentity) -> String {
        return "\(identity.volumeID):\(identity.resourceID)"
    }

    public func fetchAsset(byIdentity identity: FileIdentity, includingModified: Bool) async throws -> VideoAsset? {
        let key = identityKey(identity)
        guard let asset = assetsByIdentityKey[key] else { return nil }
        if includingModified || asset.fileIdentity.isUnchanged(comparedTo: identity) {
            return asset
        }
        return nil
    }

    public func loadAnalysis(id: UUID) async throws -> VideoAsset? {
        return assetsByID[id]
    }

    public func cachedHashes(for assets: [VideoAsset]) async throws -> [UUID: ExactDuplicateEngine.CachedHash] {
        var result: [UUID: ExactDuplicateEngine.CachedHash] = [:]
        for asset in assets {
            if let pair = hashesByAssetID[asset.id], let quick = pair.quick, let full = pair.full {
                result[asset.id] = ExactDuplicateEngine.CachedHash(quick: quick, full: full)
            }
        }
        return result
    }

    public func saveAnalysis(_ asset: VideoAsset) async throws {
        assetsByID[asset.id] = asset
        assetsByIdentityKey[identityKey(asset.fileIdentity)] = asset
    }

    public func recordHashes(assetID: UUID, quick: String?, full: String?) async throws {
        hashesByAssetID[assetID] = (quick: quick, full: full)
    }

    public func pruneAnalysis(in roots: [URL], keeping: Set<UUID>) async throws {
        assetsByID = assetsByID.filter { keeping.contains($0.key) }
        assetsByIdentityKey = assetsByIdentityKey.filter { keeping.contains($0.value.id) }
        hashesByAssetID = hashesByAssetID.filter { keeping.contains($0.key) }
    }

    public func saveResults(clusters: [DuplicateCluster], matches: [MatchResult]) async throws {
        self.savedClusters = clusters
        self.savedMatches = matches
    }

    public func getResults() async -> (clusters: [DuplicateCluster], matches: [MatchResult]) {
        return (savedClusters, savedMatches)
    }
}
