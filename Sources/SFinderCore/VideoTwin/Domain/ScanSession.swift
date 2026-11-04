import Foundation

/// A scan session — represents one scan run over one or more roots.
public struct ScanSession: Sendable, Identifiable, Codable {
    public let id: UUID
    public let roots: [ScanRoot]
    public var startedAt: Date
    public var completedAt: Date?
    public var state: ScanSessionState
    public var progress: ScanProgress

    public init(
        id: UUID = UUID(),
        roots: [ScanRoot],
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        state: ScanSessionState = .notStarted,
        progress: ScanProgress = ScanProgress()
    ) {
        self.id = id
        self.roots = roots
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.state = state
        self.progress = progress
    }
}

public enum ScanSessionState: String, Sendable, Codable {
    case notStarted
    case discovering
    case analyzing
    case matching
    case clustering
    case paused
    case completed
    case cancelled
    case failed
}

public struct ScanProgress: Sendable, Codable {
    public var totalDiscovered: Int = 0
    public var totalAnalyzed: Int = 0
    public var exactDuplicates: Int = 0
    public var nearDuplicates: Int = 0
    public var failedFiles: Int = 0
    public var possibleMatches: Int = 0
    public var reclaimableBytes: Int64 = 0

    public init(
        totalDiscovered: Int = 0,
        totalAnalyzed: Int = 0,
        exactDuplicates: Int = 0,
        nearDuplicates: Int = 0,
        failedFiles: Int = 0,
        possibleMatches: Int = 0,
        reclaimableBytes: Int64 = 0
    ) {
        self.totalDiscovered = totalDiscovered
        self.totalAnalyzed = totalAnalyzed
        self.exactDuplicates = exactDuplicates
        self.nearDuplicates = nearDuplicates
        self.failedFiles = failedFiles
        self.possibleMatches = possibleMatches
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct ScanRoot: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public let path: URL
    /// Security-scoped bookmark data for sandbox access
    public let bookmarkData: Data?
    public var excludedSubpaths: [URL]
    public var addedAt: Date

    public init(id: UUID = UUID(), path: URL, bookmarkData: Data? = nil, excludedSubpaths: [URL] = [], addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.bookmarkData = bookmarkData
        self.excludedSubpaths = excludedSubpaths
        self.addedAt = addedAt
    }
}

extension URL {
    /// Canonicalize the existing ancestor even when the candidate file was deleted.
    public func containsFile(_ candidate: URL) -> Bool {
        func canonicalPath(_ url: URL) -> String {
            var ancestor = url
            var suffix: [String] = []
            while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
                suffix.append(ancestor.lastPathComponent)
                ancestor.deleteLastPathComponent()
            }
            var canonical = ancestor.resolvingSymlinksInPath().standardizedFileURL
            for component in suffix.reversed() { canonical.appendPathComponent(component) }
            return canonical.path
        }
        let root = canonicalPath(self), path = canonicalPath(candidate)
        return path == root || root == "/" || path.hasPrefix(root + "/")
    }
}
