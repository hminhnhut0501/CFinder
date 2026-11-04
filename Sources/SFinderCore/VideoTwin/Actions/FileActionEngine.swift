import Foundation
import CryptoKit

/// Explicit actions only; revalidates files before modifying the filesystem.
public actor FileActionEngine {
    public init() {}

    public enum ActionError: LocalizedError {
        case changed, invalidLink, differentContent
        public var errorDescription: String? {
            switch self {
            case .changed: return "The file changed since scanning. Scan again before continuing."
            case .invalidLink: return "Hard links require two distinct regular files on the same volume."
            case .differentContent: return "The files are not byte-identical. Hard-link replacement was refused."
            }
        }
    }

    private func validate(_ asset: VideoAsset) async throws {
        let values = try asset.path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ActionError.changed }
        let current = try await FileIdentityResolver().resolve(url: asset.path)
        guard current.isUnchanged(comparedTo: asset.fileIdentity) else { throw ActionError.changed }
    }

    public func trash(_ asset: VideoAsset) async throws {
        try await validate(asset)
        try Task.checkCancellation()
        try FileManager.default.trashItem(at: asset.path, resultingItemURL: nil)
    }

    public func replaceWithHardLink(removing asset: VideoAsset, keeping keeper: VideoAsset, operationID: UUID = UUID()) async throws {
        try await validate(asset)
        try await validate(keeper)
        guard asset.fileIdentity.volumeID == keeper.fileIdentity.volumeID,
              !asset.fileIdentity.sameFile(as: keeper.fileIdentity), asset.path != keeper.path else { throw ActionError.invalidLink }
        let source = open(keeper.path.path, O_RDONLY | O_NOFOLLOW)
        guard source >= 0 else { throw ActionError.changed }
        defer { close(source) }
        let destination = open(asset.path.path, O_RDONLY | O_NOFOLLOW)
        guard destination >= 0 else { throw ActionError.changed }
        defer { close(destination) }
        try validateDescriptor(source, asset: keeper)
        try validateDescriptor(destination, asset: asset)
        guard try digest(destination) == digest(source) else { throw ActionError.differentContent }
        try validateDescriptor(source, asset: keeper)
        try validateDescriptor(destination, asset: asset)
        try await validate(asset)
        try await validate(keeper)
        try Task.checkCancellation()
        let manager = FileManager.default
        let staged = asset.path.deletingLastPathComponent().appendingPathComponent(".videotwin-link-" + operationID.uuidString)
        try manager.linkItem(at: keeper.path, to: staged)
        defer { try? manager.removeItem(at: staged) }
        let stagedIdentity = try await FileIdentityResolver().resolve(url: staged)
        guard stagedIdentity.sameFile(as: keeper.fileIdentity) else { throw ActionError.changed }
        try await validate(asset)
        try validateDescriptor(source, asset: keeper)
        // Atomic rename replaces the destination only after the link exists.
        guard rename(staged.path, asset.path.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    func discardStagedLink(for record: FileActionRecord) async throws {
        guard let keeper = record.keeper else { return }
        let staged = record.asset.path.deletingLastPathComponent().appendingPathComponent(".videotwin-link-" + record.id.uuidString)
        guard FileManager.default.fileExists(atPath: staged.path) else { return }
        let values = try staged.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ActionError.changed }
        let identity = try await FileIdentityResolver().resolve(url: staged)
        guard identity.sameFile(as: keeper.fileIdentity) else { throw ActionError.changed }
        try FileManager.default.removeItem(at: staged)
    }

    private func validateDescriptor(_ descriptor: Int32, asset: VideoAsset) throws {
        var st = stat()
        guard fstat(descriptor, &st) == 0, st.st_mode & S_IFMT == S_IFREG,
              st.st_ino == asset.fileIdentity.resourceID, st.st_size == asset.fileIdentity.fileSize else { throw ActionError.changed }
        let time = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
        guard time == asset.fileIdentity.modificationDate.timeIntervalSince1970 else { throw ActionError.changed }
    }

    private func digest(_ descriptor: Int32) throws -> Data {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.seek(toOffset: 0)
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 262144), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        return Data(hash.finalize())
    }
}
