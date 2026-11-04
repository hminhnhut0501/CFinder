import Foundation
import OSLog

/// Resolves stable identity for a file so we can detect renames,
/// hard links, and unchanged files without re-hashing.
///
/// Identity = inode + volume + fileSize + mtime
/// A matching identity means "very likely the same file content".
public actor FileIdentityResolver {
    public init() {}
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "scanner")

    // MARK: - Public API

    /// Resolves FileIdentity for a URL.
    /// - Parameter url: Must be a regular file (not directory/symlink).
    /// - Returns: FileIdentity or throws if stat/resourceValues fail.
    public func resolve(url: URL) throws -> FileIdentity {
        var st = stat()
        guard stat(url.path, &st) == 0 else {
            let errMsg = String(cString: strerror(errno))
            throw IdentityError.statFailed(url: url, message: errMsg)
        }

        // Volume identifier: use volume URL path as stable string
        let volumeID: String
        if let volValues = try? url.resourceValues(forKeys: [.volumeIdentifierKey]),
           let volID = volValues.volumeIdentifier {
            volumeID = "\(volID)"
        } else {
            // Fallback: use device number from stat
            volumeID = "dev:\(st.st_dev)"
        }

        let mtime = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec)
                         + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000)

        return FileIdentity(
            resourceID: st.st_ino,
            volumeID: volumeID,
            fileSize: st.st_size,
            modificationDate: mtime
        )
    }

    /// Batch resolve for multiple URLs.
    public func resolve(urls: [URL]) async -> [(url: URL, identity: FileIdentity?, error: Error?)] {
        var results: [(url: URL, identity: FileIdentity?, error: Error?)] = []
        results.reserveCapacity(urls.count)
        
        for (index, url) in urls.enumerated() {
            do {
                let identity = try resolve(url: url)
                results.append((url, identity, nil))
            } catch {
                logger.warning("Identity resolution failed for \(url.lastPathComponent): \(error)")
                results.append((url, nil, error))
            }
            
            if index % 100 == 0 {
                await Task.yield()
            }
        }
        
        return results
    }

    // MARK: - Errors

    enum IdentityError: LocalizedError {
        case statFailed(url: URL, message: String)

        var errorDescription: String? {
            switch self {
            case .statFailed(let url, let msg):
                return "stat() failed for \(url.lastPathComponent): \(msg)"
            }
        }
    }
}
