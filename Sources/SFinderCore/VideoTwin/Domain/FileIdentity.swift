import Foundation

/// Stable identity for a file using filesystem attributes.
/// Combination of inode + volume + size + mtime + quick fingerprint
/// allows detecting renames without full re-analysis.
public struct FileIdentity: Sendable, Hashable, Codable {
    /// inode number
    public let resourceID: UInt64
    /// volume UUID or mount path hash
    public let volumeID: String
    /// File size in bytes
    public let fileSize: Int64
    /// Modification time
    public let modificationDate: Date
    /// BLAKE3 of first+middle+last 1MiB
    public var quickFingerprint: String?

    public init(resourceID: UInt64, volumeID: String, fileSize: Int64, modificationDate: Date, quickFingerprint: String? = nil) {
        self.resourceID = resourceID
        self.volumeID = volumeID
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.quickFingerprint = quickFingerprint
    }

    /// True if core identity (inode+volume) matches, ignoring mtime changes.
    public func sameFile(as other: FileIdentity) -> Bool {
        resourceID == other.resourceID && volumeID == other.volumeID
    }

    /// True if the file appears unmodified since last scan.
    public func isUnchanged(comparedTo other: FileIdentity) -> Bool {
        sameFile(as: other)
            && fileSize == other.fileSize
            && modificationDate == other.modificationDate
    }
}
