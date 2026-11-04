import Foundation
import OSLog
import UniformTypeIdentifiers

/// Discovers video files recursively in one or more directories.
/// - Async stream: yields results progressively without blocking.
/// - Handles symlinks and prevents recursion loops via visited inode set.
/// - Filters by extension/UTI; metadata decoding validates media later.
public actor FileDiscovery {
    // MARK: - Supported extensions (initial set per spec §7)
    public static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "webm",
        "ts", "mts", "m2ts", "mpg", "mpeg", "wmv", "flv"
    ]

    // MARK: - UTIs for additional validation
    private static let videoUTIs: [UTType] = [
        .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi
    ]

    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "scanner")

    /// Excluded subpath URLs (pre-resolved to canonical paths).
    private var excludedPaths: Set<URL> = []

    func setExcludedPaths(_ paths: [URL]) {
        excludedPaths = Set(paths.map { $0.resolvingSymlinksInPath() })
    }

    // MARK: - Public API

    /// Returns an AsyncThrowingStream of discovered file URLs.
    /// Call from a Task; cancel the Task to stop discovery.
    func discoverFiles(in roots: [URL]) -> AsyncThrowingStream<URL, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let producer = Task {
                var visitedInodes = Set<InodeKey>()
                for root in roots {
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    await self.walk(
                        directory: root,
                        visited: &visitedInodes,
                        continuation: continuation
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }

    // MARK: - Private

    private func walk(
        directory: URL,
        visited: inout Set<InodeKey>,
        continuation: AsyncThrowingStream<URL, Error>.Continuation
    ) async {
        let canonical = directory.resolvingSymlinksInPath()

        // Exclusion check
        if excludedPaths.contains(canonical) {
            logger.debug("Excluding: \(canonical.path)")
            return
        }

        // Symlink / loop detection via inode
        guard let inodeKey = InodeKey(url: canonical) else {
            logger.warning("Cannot stat: \(canonical.path)")
            return
        }
        guard visited.insert(inodeKey).inserted else {
            logger.debug("Loop detected, skipping: \(canonical.path)")
            return
        }

        guard !Task.isCancelled else { return }

        let fm = FileManager.default
        // A drop can contain individual files as well as directories.
        guard let rootValues = try? canonical.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey, .isSymbolicLinkKey]) else { return }
        if rootValues.isDirectory != true {
            guard rootValues.isReadable == true, rootValues.isSymbolicLink != true, isLikelyVideoFile(canonical) else { return }
            await emit(canonical, to: continuation)
            return
        }
        guard let enumerator = fm.enumerator(
            at: canonical,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .fileResourceIdentifierKey,
                .volumeIdentifierKey,
                .isReadableKey
            ],
            options: [.skipsPackageDescendants],
            errorHandler: { [weak self] url, error in
                self?.logger.warning("Enumerator error at \(url.path): \(error)")
                return true  // continue enumeration
            }
        ) else {
            logger.warning("Cannot enumerate: \(canonical.path)")
            return
        }

        var fileCount = 0

        while let fileURL = enumerator.nextObject() as? URL {
            guard !Task.isCancelled else { break }
            fileCount += 1

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .isReadableKey
                ])

                // Skip unreadable
                guard resourceValues.isReadable == true else { continue }

                // Handle directories: check exclusion and loops
                if resourceValues.isDirectory == true {
                    let canonicalSub = fileURL.resolvingSymlinksInPath()
                    if excludedPaths.contains(canonicalSub) {
                        enumerator.skipDescendants()
                        continue
                    }
                    if let key = InodeKey(url: canonicalSub), !visited.insert(key).inserted {
                        logger.debug("Loop: skipping \(canonicalSub.path)")
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard resourceValues.isSymbolicLink != true else { continue }
                // File: check extension first (cheap), then UTI
                if isLikelyVideoFile(fileURL) {
                    guard let key = InodeKey(url: fileURL), visited.insert(key).inserted else { continue }
                    await emit(fileURL, to: continuation)
                }
            } catch {
                logger.warning("Resource values error at \(fileURL.path): \(error)")
            }

            // Yield to event loop periodically
            if fileCount % 100 == 0 {
                await Task.yield()
            }
        }
    }

    private func emit(_ url: URL, to continuation: AsyncThrowingStream<URL, Error>.Continuation) async {
        while !Task.isCancelled {
            switch continuation.yield(url) {
            case .enqueued, .terminated: return
            case .dropped: try? await Task.sleep(for: .milliseconds(2))
            @unknown default: return
            }
        }
    }

    /// Quick video file check: extension match (primary) + UTI conformance (secondary).
    /// Does NOT open the file — cheap filter only.
    private func isLikelyVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }

        // Extension fast path
        if Self.videoExtensions.contains(ext) { return true }

        // UTI fallback for files without standard extensions
        if let utType = UTType(filenameExtension: ext) {
            return Self.videoUTIs.contains(where: { utType.conforms(to: $0) })
        }
        return false
    }
}

// MARK: - Inode identity for loop detection

private struct InodeKey: Hashable {
    let inode: UInt64
    let device: UInt32

    init?(url: URL) {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        self.inode = st.st_ino
        self.device = UInt32(bitPattern: st.st_dev)
    }
}
