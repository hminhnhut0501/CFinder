import Foundation
import OSLog
import CryptoKit

/// Stage 1 of the pipeline: Exact duplicate detection WITHOUT video decoding.
///
/// Algorithm (per spec §9):
///   1. Group files by fileSize
///   2. Skip size-unique files
///   3. For collisions: compute SHA-256(first1MiB + middle1MiB + last1MiB) = QuickHash
///   4. For QuickHash collisions: compute full SHA-256
///   5. Full hash match → EXACT_DUPLICATE, Similarity=100%, Confidence=CERTAIN
///
/// No video decoding. No visual analysis. Pure filesystem hashing.
public actor ExactDuplicateEngine {
    public init() {}
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "scanner")

    // MARK: - Constants

    /// Chunk size for quick hash (1 MiB per spec)
    public static let chunkSize: Int = 1 * 1024 * 1024

    // MARK: - Public API

    public struct CachedHash: Sendable {
        public let quick: String
        public let full: String
        public init(quick: String, full: String) {
            self.quick = quick
            self.full = full
        }
    }

    public struct ExactGroup: Sendable {
        public let quickHash: String
        public let fullHash: String
        public let assets: [VideoAsset]

        public var count: Int { assets.count }

        public init(quickHash: String, fullHash: String, assets: [VideoAsset]) {
            self.quickHash = quickHash
            self.fullHash = fullHash
            self.assets = assets
        }
    }

    /// Finds exact duplicates among `assets` using size grouping + SHA-256.
    /// Returns groups of 2+ files with identical content.
    public func findExactDuplicates(
        assets: [VideoAsset],
        pool: WorkerPool,
        pauseToken: PauseToken,
        cachedHashes: [UUID: CachedHash] = [:]
    ) async -> [ExactGroup] {
        // Step 1: Group by file size
        var sizeGroups: [Int64: [VideoAsset]] = [:]
        for asset in assets {
            let size = asset.fileIdentity.fileSize
            sizeGroups[size, default: []].append(asset)
        }

        // Step 2: Skip unique sizes
        let candidates = sizeGroups.filter { $0.value.count > 1 }
        logger.debug("Size collision groups: \(candidates.count) (from \(assets.count) files)")

        if candidates.isEmpty { return [] }

        // Step 3: Compute QuickHash for size-collision groups
        var quickHashGroups: [String: [VideoAsset]] = [:]
        for (_, group) in candidates {
            for asset in group {
                guard !Task.isCancelled else { return [] }
                await pauseToken.checkPause()

                do {
                    let qHash: String
                    if let cached = cachedHashes[asset.id] { qHash = cached.quick }
                    else { qHash = try await pool.withWorker {
                        try await quickSHA256(url: asset.path, fileSize: asset.fileIdentity.fileSize)
                    } }
                    quickHashGroups[qHash, default: []].append(asset)
                } catch {
                    logger.warning("QuickHash failed for \(asset.path.lastPathComponent): \(error)")
                }
            }
        }

        // Step 4: Full SHA-256 for QuickHash collisions
        var results: [ExactGroup] = []
        var fullHashGroups: [String: (quickHash: String, assets: [VideoAsset])] = [:]

        for (quickHash, group) in quickHashGroups where group.count > 1 {
            for asset in group {
                guard !Task.isCancelled else { return results }
                await pauseToken.checkPause()

                do {
                    let fHash: String
                    if let cached = cachedHashes[asset.id] { fHash = cached.full }
                    else { fHash = try await pool.withWorker {
                        try await fullSHA256(url: asset.path)
                    } }
                    if fullHashGroups[fHash] == nil {
                        fullHashGroups[fHash] = (quickHash, [])
                    }
                    fullHashGroups[fHash]?.assets.append(asset)
                } catch {
                    logger.warning("FullHash failed for \(asset.path.lastPathComponent): \(error)")
                }
            }
        }

        // Step 5: Collect groups with 2+ files = EXACT_DUPLICATE
        for (fullHash, entry) in fullHashGroups where entry.assets.count > 1 {
            results.append(ExactGroup(
                quickHash: entry.quickHash,
                fullHash: fullHash,
                assets: entry.assets
            ))
            logger.info("Exact duplicate group: \(entry.assets.count) files, hash \(fullHash.prefix(12))…")
        }

        return results
    }

    // MARK: - SHA-256 Hashing

    /// Quick hash: SHA-256 of (fileSize bytes as prefix) + first + middle + last chunks.
    /// Returns hex string.
    private func quickSHA256(url: URL, fileSize: Int64) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw HashError.cannotOpenFile(url)
        }
        defer { try? handle.close() }

        var hasher = SHA256()

        // Encode file size as 8-byte big-endian prefix (domain separation)
        withUnsafeBytes(of: fileSize.bigEndian) { hasher.update(bufferPointer: $0) }

        // First chunk
        if let first = try handle.read(upToCount: Self.chunkSize) {
            hasher.update(data: first)
        }

        // Middle chunk
        let mid = max(0, Int(fileSize) / 2 - Self.chunkSize / 2)
        if mid > 0 && Int(fileSize) > Self.chunkSize * 2 {
            try handle.seek(toOffset: UInt64(mid))
            if let middle = try handle.read(upToCount: Self.chunkSize) {
                hasher.update(data: middle)
            }
        }

        // Last chunk
        if Int(fileSize) > Self.chunkSize {
            let lastOffset = max(0, Int(fileSize) - Self.chunkSize)
            try handle.seek(toOffset: UInt64(lastOffset))
            if let last = try handle.read(upToCount: Self.chunkSize) {
                hasher.update(data: last)
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Full SHA-256 of entire file content.
    private func fullSHA256(url: URL) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw HashError.cannotOpenFile(url)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        let bufferSize = 256 * 1024  // 256 KiB read buffer

        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: bufferSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Errors

    enum HashError: LocalizedError {
        case cannotOpenFile(URL)

        var errorDescription: String? {
            switch self {
            case .cannotOpenFile(let url):
                return "Cannot open file for hashing: \(url.lastPathComponent)"
            }
        }
    }
}

