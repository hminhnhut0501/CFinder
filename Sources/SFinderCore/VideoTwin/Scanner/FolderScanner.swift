import Foundation
import OSLog

/// Top-level scan coordinator.
/// Manages the lifecycle of one ScanSession:
/// discover → identity → exact hash → metadata → fingerprint → match → cluster
///
/// All work is async and bounded via WorkerPool.
/// Cancel the Task returned by `startScan()` to cancel the scan.
/// Pause/resume are supported via PauseToken.
@MainActor
public final class FolderScanner: ObservableObject {
    // MARK: - Published state
    @Published public private(set) var session: ScanSession
    @Published public private(set) var clusters: [DuplicateCluster] = []
    @Published public private(set) var assetsByID: [UUID: VideoAsset] = [:]
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var failureMessage: String?
    @Published public private(set) var isPaused: Bool = false

    @Published public private(set) var activity = "Preparing scan"
    @Published public private(set) var completedPairs = 0
    @Published public private(set) var totalPairs = 0
    @Published public private(set) var lastActivityAt = Date()

    // MARK: - Dependencies
    private let discovery: FileDiscovery
    private let identityResolver: FileIdentityResolver
    private let hashEngine: ExactDuplicateEngine
    private let storage: VideoTwinStorage
    private let resourceController: ResourceController
    private let config: SimilarityConfiguration

    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "scanner")

    // MARK: - Concurrency control
    private var scanTask: Task<Void, Error>?
    private var resumeState: ScanSessionState = .discovering
    private var pauseToken: PauseToken = PauseToken()

    // MARK: - Init

    public init(
        roots: [ScanRoot],
        storage: VideoTwinStorage = InMemoryVideoTwinStorage(),
        resourceController: ResourceController,
        config: SimilarityConfiguration = .default
    ) {
        self.discovery = FileDiscovery()
        self.identityResolver = FileIdentityResolver()
        self.hashEngine = ExactDuplicateEngine()
        self.storage = storage
        self.resourceController = resourceController
        self.config = config
        self.session = ScanSession(
            id: UUID(),
            roots: roots,
            startedAt: Date(),
            state: .notStarted,
            progress: ScanProgress()
        )
    }

    // MARK: - Lifecycle

    public func startScan() {
        guard !isRunning else { return }
        isRunning = true
        isPaused = false
        failureMessage = nil
        pauseToken = PauseToken()
        completedPairs = 0; totalPairs = 0
        activity = "Discovering video files"; lastActivityAt = Date()
        session.progress = ScanProgress()
        session.completedAt = nil
        session.state = .discovering

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.runScanPipeline()
                await MainActor.run {
                    self.session.state = .completed
                    self.session.completedAt = Date()
                    self.isRunning = false
                    self.isPaused = false
                    self.scanTask = nil
                }
                self.logger.info("Scan completed: \(self.session.progress.totalAnalyzed) files")
            } catch is CancellationError {
                await MainActor.run {
                    self.session.state = .cancelled
                    self.isRunning = false
                    self.isPaused = false
                    self.scanTask = nil
                }
                self.logger.info("Scan cancelled")
            } catch {
                await MainActor.run {
                    self.failureMessage = error.localizedDescription
                    self.session.state = .failed
                    self.isRunning = false
                    self.isPaused = false
                    self.scanTask = nil
                }
                self.logger.error("Scan failed: \(error)")
            }
        }
    }

    public func waitForCompletion() async {
        _ = try? await scanTask?.value
    }

    public func pauseScan() {
        guard isRunning, !isPaused else { return }
        resumeState = session.state
        isPaused = true
        session.state = .paused
        pauseToken.pause()
        logger.info("Scan paused")
    }

    public func resumeScan() {
        guard isRunning, isPaused else { return }
        isPaused = false
        session.state = resumeState
        pauseToken.resume()
        logger.info("Scan resumed")
    }

    public func cancelScan() {
        scanTask?.cancel()
        pauseToken.resume()  // unblock any paused workers
    }

    private func setPhase(_ state: ScanSessionState) {
        lastActivityAt = Date()
        resumeState = state
        session.state = isPaused ? .paused : state
    }

    // MARK: - Pipeline

    nonisolated private func runScanPipeline() async throws {
        let roots = await session.roots

        // Stage 1: Discover files
        logger.info("Stage: DISCOVER")
        let rootURLs = roots.compactMap { root -> URL? in
            if let bookmark = root.bookmarkData {
                var isStale = false
                if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    _ = resolved.startAccessingSecurityScopedResource()
                    return resolved
                }
            }
            let url = root.path
            _ = url.startAccessingSecurityScopedResource()
            return url
        }

        let savedBookmarks = await MainActor.run { UserDefaults.standard.array(forKey: "scanBookmarks") as? [Data] ?? [] }
        let extraURLs = savedBookmarks.compactMap { data -> URL? in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() else { return nil }
            return url
        }
        defer { extraURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        defer { rootURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

        await discovery.setExcludedPaths(roots.flatMap { $0.excludedSubpaths })

        var discoveredURLs: [URL] = []
        let stream = await discovery.discoverFiles(in: rootURLs)
        var lastUIUpdate = Date()
        var discoveredCount = 0

        for try await url in stream {
            try Task.checkCancellation()
            await pauseToken.checkPause()
            try Task.checkCancellation()
            discoveredURLs.append(url)
            discoveredCount += 1

            let now = Date()
            if now.timeIntervalSince(lastUIUpdate) > 0.1 {
                lastUIUpdate = now
                let count = discoveredCount
                await MainActor.run {
                    self.session.progress.totalDiscovered = count
                }
            }
        }
        


        let totalCount = discoveredURLs.count
        await MainActor.run {
            self.session.progress.totalDiscovered = totalCount
        }
        logger.info("Discovered \(totalCount) candidate files")

        // Stage 2: File Identity — separate new/unchanged/modified
        logger.info("Stage: FILE IDENTITY")
        let workerCount = await resourceController.recommendedDecodeWorkers()
        let pool = WorkerPool(maxConcurrency: workerCount)

        var newAssets: [VideoAsset] = []
        var reusableIDs = Set<UUID>()
        await MainActor.run { self.activity = "Checking file identities and cached analysis"; self.lastActivityAt = Date() }
        let identityResults = await identityResolver.resolve(urls: discoveredURLs)

        var seenFiles = Set<String>()
        for (url, identity, _) in identityResults {
            guard let identity else { continue }
            guard seenFiles.insert("\(identity.volumeID):\(identity.resourceID)").inserted else { continue }
            try Task.checkCancellation()

            let existing = try await storage.fetchAsset(byIdentity: identity, includingModified: true)
            var asset = VideoAsset(id: existing?.id ?? UUID(), path: url, fileIdentity: identity, analysisState: .identityResolved)
            if let existing, let cached = try await storage.loadAnalysis(id: existing.id), cached.analysisState == .qualityAnalyzed, cached.fileIdentity.isUnchanged(comparedTo: identity) {
                asset = cached
                asset.path = url
                if cached.path == url { reusableIDs.insert(asset.id) }
            }
            newAssets.append(asset)
        }

        let currentScanIDs = Set(newAssets.map(\.id))
        let cachedHashes = try await storage.cachedHashes(for: newAssets)
        logger.info("Processing \(currentScanIDs.count) scanned and \(newAssets.count - currentScanIDs.count) cached library files")

        // Stage 3: Exact duplicates (size grouping → SHA-256)
        logger.info("Stage: EXACT DUPLICATE")
        await MainActor.run { self.activity = "Verifying exact duplicates by reading file contents"; self.lastActivityAt = Date() }
        let exactGroups = await hashEngine.findExactDuplicates(
            assets: newAssets,
            pool: pool,
            pauseToken: pauseToken,
            cachedHashes: cachedHashes
        )

        for group in exactGroups {
            try Task.checkCancellation()
            await MainActor.run {
                self.session.progress.exactDuplicates += group.count - 1
            }
        }

        // Map exact duplicate followers to avoid redundant video decoding
        var exactLeaderMap: [UUID: UUID] = [:] // followerID -> leaderID
        var leaderIDs = Set<UUID>()
        for group in exactGroups {
            guard let leader = group.assets.first else { continue }
            leaderIDs.insert(leader.id)
            for asset in group.assets where asset.id != leader.id {
                exactLeaderMap[asset.id] = leader.id
            }
        }

        await setPhase(.analyzing)
        var analyzedAssets: [VideoAsset] = []
        var analyzedCount = 0, failedCount = 0
        var lastAnalysisUpdate = Date.distantPast

        // Assets that actually need visual decoding (skip followers in exact groups)
        let assetsToAnalyze = newAssets.filter { exactLeaderMap[$0.id] == nil }
        var leaderAnalysisMap: [UUID: VideoAsset] = [:]

        // Continuous Work Pipeline (Zero Straggler Waiting):
        // Maintain continuous worker stream. As soon as any worker completes an asset,
        // immediately feed the next pending asset into the task group.
        let workerConcurrency = min(8, max(2, await resourceController.recommendedDecodeWorkers()))
        await withTaskGroup(of: VideoAsset.self) { group in
            var nextIndex = 0
            while nextIndex < min(workerConcurrency, assetsToAnalyze.count) {
                let asset = assetsToAnalyze[nextIndex]
                nextIndex += 1
                group.addTask {
                    await VideoAnalyzer().analyze(asset)
                }
            }
            
            while let asset = await group.next() {
                if currentScanIDs.contains(asset.id) {
                    if !reusableIDs.contains(asset.id) { try? await storage.saveAnalysis(asset) }
                    analyzedCount += 1
                    if asset.analysisState == .failed { failedCount += 1 }
                }
                if leaderIDs.contains(asset.id) {
                    leaderAnalysisMap[asset.id] = asset
                }
                analyzedAssets.append(asset)
                
                // Immediately feed next asset to keep all workers 100% busy
                if nextIndex < assetsToAnalyze.count {
                    let nextAsset = assetsToAnalyze[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await VideoAnalyzer().analyze(nextAsset)
                    }
                }
                
                if Date().timeIntervalSince(lastAnalysisUpdate) >= 0.2 || analyzedCount == assetsToAnalyze.count {
                    lastAnalysisUpdate = Date()
                    let count = analyzedCount, failed = failedCount
                    await MainActor.run {
                        self.session.progress.totalAnalyzed = count
                        self.session.progress.failedFiles = failed
                        self.activity = "Analyzed \(count)/\(assetsToAnalyze.count) files"
                        self.lastActivityAt = Date()
                    }
                }
            }
        }

        // For exact duplicate followers: clone analysis from their leader
        for asset in newAssets where exactLeaderMap[asset.id] != nil {
            var follower = asset
            if let leaderID = exactLeaderMap[asset.id], let leaderAsset = leaderAnalysisMap[leaderID] {
                follower.metadata = leaderAsset.metadata
                follower.audioMetadata = leaderAsset.audioMetadata
                follower.fingerprints = leaderAsset.fingerprints
                follower.quality = leaderAsset.quality
                follower.analysisState = leaderAsset.analysisState
                follower.errorState = leaderAsset.errorState
            }
            analyzedAssets.append(follower)
            if currentScanIDs.contains(follower.id) && !reusableIDs.contains(follower.id) {
                try? await storage.saveAnalysis(follower)
            }
        }
        let scannedIDs = currentScanIDs
        var matches: [MatchResult] = []
        var exactHashes: [UUID: String] = [:]
        for group in exactGroups {
            guard let leader = group.assets.first else { continue }
            for asset in group.assets {
                try await storage.recordHashes(assetID: asset.id, quick: group.quickHash, full: group.fullHash)
                exactHashes[asset.id] = group.fullHash
                if asset.id != leader.id { matches.append(.exact(leader.id, asset.id)) }
            }
        }
        await setPhase(.matching)
        let generator = CandidateGenerator(config: config)
        let matcher = MatchEngine(config: config)
        await MainActor.run { self.activity = "Preparing visual comparison candidates"; self.lastActivityAt = Date() }
        let candidates = await generator.generateCandidates(from: analyzedAssets)
        let partial = await generator.generatePartialCandidates(from: analyzedAssets)
        var byID = Dictionary(uniqueKeysWithValues: analyzedAssets.map { ($0.id, $0) })
        let pairs = Set(candidates + partial).filter { pair in
            guard scannedIDs.contains(pair.assetAID) || scannedIDs.contains(pair.assetBID) else { return false }
            if let hash = exactHashes[pair.assetAID], hash == exactHashes[pair.assetBID] { return false }
            guard let a = byID[pair.assetAID], let b = byID[pair.assetBID] else { return false }
            return !a.fingerprints.isEmpty && !b.fingerprints.isEmpty
        }.sorted { ($0.assetAID.uuidString, $0.assetBID.uuidString) < ($1.assetAID.uuidString, $1.assetBID.uuidString) }
        await MainActor.run { self.totalPairs = pairs.count }
        var checked = 0
        var visualMatches = 0
        var lastPairUpdate = Date.distantPast
        let maxMatchConcurrency = max(4, min(16, ProcessInfo.processInfo.activeProcessorCount * 2))
        let pause = await MainActor.run { self.pauseToken }
        let assetMap = byID

        try await withThrowingTaskGroup(of: MatchResult?.self) { group in
            var nextIndex = 0
            while nextIndex < min(maxMatchConcurrency, pairs.count) {
                let pair = pairs[nextIndex]
                nextIndex += 1
                if let a = assetMap[pair.assetAID], let b = assetMap[pair.assetBID] {
                    group.addTask {
                        try Task.checkCancellation()
                        await pause.checkPause()
                        try Task.checkCancellation()
                        return await matcher.match(assetA: a, assetB: b)
                    }
                }
            }

            while let result = try await group.next() {
                if let match = result {
                    matches.append(match)
                    visualMatches += 1
                }
                checked += 1

                if nextIndex < pairs.count {
                    let pair = pairs[nextIndex]
                    nextIndex += 1
                    if let a = assetMap[pair.assetAID], let b = assetMap[pair.assetBID] {
                        let label = Self.compactPairActivity(a: a.path.lastPathComponent, b: b.path.lastPathComponent, current: checked + 1, total: pairs.count)
                        if Date().timeIntervalSince(lastPairUpdate) >= 0.1 {
                            await MainActor.run {
                                self.activity = label
                                self.lastActivityAt = Date()
                            }
                        }
                        group.addTask {
                            try Task.checkCancellation()
                            await pause.checkPause()
                            try Task.checkCancellation()
                            return await matcher.match(assetA: a, assetB: b)
                        }
                    }
                }

                let count = checked, found = visualMatches
                if Date().timeIntervalSince(lastPairUpdate) >= 0.1 || checked == pairs.count {
                    lastPairUpdate = Date()
                    await MainActor.run {
                        self.completedPairs = count
                        self.session.progress.nearDuplicates = found
                        self.lastActivityAt = Date()
                    }
                }
            }
        }
        await setPhase(.clustering)
        await MainActor.run { self.activity = "Grouping matches and recommending best copies" }
        let dismissedWatermarks = await MainActor.run { Set(UserDefaults.standard.stringArray(forKey: "dismissedWatermarkFiles") ?? []) }
        for id in byID.keys {
            if var mark = byID[id]?.watermark, let asset = byID[id] {
                mark.dismissed = dismissedWatermarks.contains(WatermarkPolicy.dismissalKey(asset))
                byID[id]?.watermark = mark
            }
        }
        for asset in byID.values { try await storage.saveAnalysis(asset) }
        let clustering = ClusterEngine(config: config)
        let recommender = BestCopyRecommender()
        var clusters: [DuplicateCluster] = []
        let certifiedExact: [[UUID]] = exactGroups.map { grp in grp.assets.map { $0.id } }
        for cluster in await clustering.cluster(matches: matches, certifiedExactGroups: certifiedExact) {
            clusters.append(await recommender.recommend(for: cluster, assets: byID))
        }
        try Task.checkCancellation()
        try await storage.pruneAnalysis(in: [URL(fileURLWithPath: "/")], keeping: scannedIDs)
        await MainActor.run { self.activity = "Saving scan results"; self.lastActivityAt = Date() }
        try await storage.saveResults(clusters: clusters, matches: matches)
        let finalClusters = clusters
        let finalAssets = byID
        await MainActor.run {
            self.clusters = finalClusters
            self.assetsByID = finalAssets
        }
        let nearCount = matches.filter { $0.matchType != .exact }.count
        let reclaimable = clusters.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        await MainActor.run {
            self.session.progress.nearDuplicates = nearCount
            self.session.progress.reclaimableBytes = reclaimable
        }
    }
    
    // MARK: - Safe Filename Truncation for Compact Activity Labels
    
    nonisolated public static func compactPairActivity(a: String, b: String, current: Int, total: Int) -> String {
        let nameA = truncateFilename(a, maxLen: 14)
        let nameB = truncateFilename(b, maxLen: 14)
        return "So sánh (\(current)/\(total)): \(nameA) ↔ \(nameB)"
    }
    
    nonisolated public static func truncateFilename(_ name: String, maxLen: Int = 16) -> String {
        guard name.count > maxLen else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        let keep = max(3, maxLen - (ext.isEmpty ? 3 : ext.count + 4))
        let prefix = String(base.prefix(keep))
        return ext.isEmpty ? "\(prefix)..." : "\(prefix)...\(ext)"
    }
}

// MARK: - Pause Token

/// Lock-protected pause state makes pause/resume synchronous and cancellation-aware.
public final class PauseToken: @unchecked Sendable {
    public init() {}
    private let lock = NSLock()
    private var paused = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    public func pause() { lock.withLock { paused = true } }
    public func resume() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            paused = false
            let pending = Array(waiters.values); waiters.removeAll(); return pending
        }
        pending.forEach { $0.resume() }
    }
    public func checkPause() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let wait = lock.withLock { () -> Bool in
                    if paused && !Task.isCancelled { waiters[id] = continuation; return true }
                    return false
                }
                if !wait { continuation.resume() }
            }
        } onCancel: {
            let continuation = self.lock.withLock { self.waiters.removeValue(forKey: id) }
            continuation?.resume()
        }
    }
}
