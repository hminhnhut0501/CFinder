import Foundation

/// Shared validation for both individual and batch review actions.
public enum ReviewSelection {
    /// Global extras exclude every recommended keeper, even across overlapping groups.
    public static func extras(clusters: [DuplicateCluster], assets: [UUID: VideoAsset]) -> Set<UUID> {
        let keepers = Set(clusters.compactMap(\.recommendedKeepID))
        return Set(clusters.flatMap { $0.members.map(\.assetID) })
            .subtracting(keepers).filter { assets[$0] != nil }
    }

    public static func rejection(ids: Set<UUID>, clusters: [DuplicateCluster], assets: [UUID: VideoAsset]) -> String? {
        guard !ids.isEmpty else { return "Select at least one file." }
        guard ids.allSatisfy({ assets[$0] != nil }) else { return "Some selected files are no longer in the library." }
        return nil
    }
}

public struct TrashBatchReport: Sendable {
    var succeeded: Set<UUID> = []
    var failures: [UUID: String] = [:]
}
