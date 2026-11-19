import SwiftUI
import Combine
import SFinderCore

public enum ClusterFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case exact = "Trùng 100%"
    case nearDuplicate = "Tương đồng"
    
    public var id: String { rawValue }
}

@MainActor
public final class VideoTwinStudioViewModel: ObservableObject {
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var activity: String = "Sẵn sàng quét"
    @Published public private(set) var progress: ScanProgress = ScanProgress()
    @Published public private(set) var clusters: [DuplicateCluster] = []
    @Published public private(set) var assetsByID: [UUID: VideoAsset] = [:]
    
    @Published public var selectedClusterID: UUID?
    @Published public var selectedForRemoval: Set<UUID> = []
    @Published public var sourceFolderPath: String? = nil
    @Published public var activeDualComparison: (assetA: VideoAsset, assetB: VideoAsset, offset: Double)?
    @Published public var quickViewURL: URL? = nil
    @Published public var searchQuery: String = ""
    @Published public var filterTab: ClusterFilter = .all
    @Published public var statusToast: String?
    @Published public var errorMessage: String?
    
    public var sourceFolderName: String? {
        guard let path = sourceFolderPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    
    public var detectedFolders: [(url: URL, path: String, name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for asset in assetsByID.values {
            let dirPath = asset.path.deletingLastPathComponent().path
            counts[dirPath, default: 0] += 1
        }
        return counts.map { (path, count) in
            let url = URL(fileURLWithPath: path)
            return (url: url, path: path, name: url.lastPathComponent, count: count)
        }.sorted { $0.count > $1.count }
    }
    
    public func isAssetInSourceFolder(_ asset: VideoAsset) -> Bool {
        guard let source = sourceFolderPath, !source.isEmpty else { return false }
        let assetDirPath = asset.path.deletingLastPathComponent().path
        return assetDirPath == source || assetDirPath.hasPrefix(source + "/")
    }
    
    public func setSourceFolder(url: URL?) {
        guard let url else {
            clearSourceFolder()
            return
        }
        self.sourceFolderPath = url.path
        self.statusToast = "Đã đặt '\(url.lastPathComponent)' làm Folder Nguồn bảo vệ"
        autoSelectAllRecommended()
    }
    
    public func clearSourceFolder() {
        self.sourceFolderPath = nil
        self.statusToast = "Đã hủy Folder Nguồn"
        autoSelectAllRecommended()
    }
    
    @Published public var targetURLs: [URL] = []
    @Published public var hasStartedScanOnce: Bool = false
    @Published public var hasNewSourcesPendingScan: Bool = false
    
    private var scanner: FolderScanner?
    private var cancellables = Set<AnyCancellable>()
    private let fileActionEngine = FileActionEngine()
    
    public init(urls: [URL]) {
        self.targetURLs = urls.map { $0.standardizedFileURL }
    }
    
    public struct TargetRootInfo: Identifiable, Hashable {
        public let id: String
        public let url: URL
        public let name: String
        public let isExternal: Bool
        public let volumeName: String
        public let path: String
        public let isDirectory: Bool
        
        public init(url: URL) {
            self.id = url.path
            self.url = url
            self.name = url.lastPathComponent
            self.isExternal = url.isExternalVolume
            self.volumeName = url.volumeName
            self.path = url.path
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            self.isDirectory = isDir.boolValue
        }
    }
    
    public var targetRootsInfo: [TargetRootInfo] {
        targetURLs.map { TargetRootInfo(url: $0) }
    }
    
    public func addTargetURLs(_ urls: [URL]) {
        let existing = Set(targetURLs.map { $0.standardizedFileURL.path })
        var added = 0
        for u in urls {
            let std = u.standardizedFileURL
            if !existing.contains(std.path) {
                targetURLs.append(std)
                added += 1
            }
        }
        if added > 0 {
            if hasStartedScanOnce {
                hasNewSourcesPendingScan = true
                statusToast = "Đã thêm \(added) nguồn mới. Bấm 'Quét lại' để cập nhật."
            } else {
                statusToast = "Đã thêm \(added) nguồn mới vào danh sách."
            }
        }
    }
    
    public func removeTargetURL(_ url: URL) {
        let p = url.standardizedFileURL.path
        targetURLs.removeAll { $0.standardizedFileURL.path == p }
        if hasStartedScanOnce {
            hasNewSourcesPendingScan = true
        }
        statusToast = "Đã bỏ '\(url.lastPathComponent)' khỏi danh sách"
    }
    
    public var selectedCluster: DuplicateCluster? {
        guard let id = selectedClusterID else { return clusters.first }
        return clusters.first(where: { $0.id == id }) ?? clusters.first
    }
    
    public var filteredClusters: [DuplicateCluster] {
        clusters.filter { cluster in
            let matchesFilter: Bool
            switch filterTab {
            case .all: matchesFilter = true
            case .exact: matchesFilter = cluster.representativeMatchType == .exact
            case .nearDuplicate: matchesFilter = cluster.representativeMatchType != .exact
            }
            
            if !matchesFilter { return false }
            if searchQuery.isEmpty { return true }
            
            return cluster.members.contains { member in
                if let asset = assetsByID[member.assetID] {
                    return asset.path.lastPathComponent.localizedCaseInsensitiveContains(searchQuery)
                }
                return false
            }
        }
    }
    
    public var totalReclaimableBytes: Int64 {
        clusters.reduce(0) { $0 + $1.reclaimableBytes }
    }
    
    public var selectedRemovalBytes: Int64 {
        selectedForRemoval.compactMap { assetsByID[$0]?.fileIdentity.fileSize }.reduce(0, +)
    }
    
    // MARK: - Scan Lifecycle
    
    public func startScan() {
        guard !targetURLs.isEmpty else { return }
        guard !isScanning else { return }
        hasStartedScanOnce = true
        hasNewSourcesPendingScan = false
        errorMessage = nil
        cancellables.removeAll()
        
        let roots = targetURLs.map { url in
            ScanRoot(id: UUID(), path: url, bookmarkData: nil, excludedSubpaths: [], addedAt: Date())
        }
        
        let storage = InMemoryVideoTwinStorage()
        let resourceController = ResourceController(profile: .balanced)
        let config = SimilarityConfiguration.default
        
        let newScanner = FolderScanner(
            roots: roots,
            storage: storage,
            resourceController: resourceController,
            config: config
        )
        self.scanner = newScanner
        
        // Bind state reactively
        newScanner.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: \.isScanning, on: self)
            .store(in: &cancellables)
            
        newScanner.$isPaused
            .receive(on: DispatchQueue.main)
            .assign(to: \.isPaused, on: self)
            .store(in: &cancellables)
            
        newScanner.$activity
            .receive(on: DispatchQueue.main)
            .assign(to: \.activity, on: self)
            .store(in: &cancellables)
            
        newScanner.$failureMessage
            .receive(on: DispatchQueue.main)
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)
            
        newScanner.$session
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sess in
                self?.progress = sess.progress
            }
            .store(in: &cancellables)
            
        newScanner.$clusters
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newClusters in
                guard let self else { return }
                self.clusters = newClusters
                if self.selectedClusterID == nil, let first = newClusters.first {
                    self.selectedClusterID = first.id
                }
                self.autoSelectDuplicatesForRemoval(in: newClusters)
            }
            .store(in: &cancellables)
            
        newScanner.$assetsByID
            .receive(on: DispatchQueue.main)
            .assign(to: \.assetsByID, on: self)
            .store(in: &cancellables)
            
        newScanner.startScan()
    }
    
    public func cancelScan() {
        scanner?.cancelScan()
        activity = "Đã dừng quét"
    }
    
    public func togglePause() {
        if isPaused {
            scanner?.resumeScan()
        } else {
            scanner?.pauseScan()
        }
    }
    
    // MARK: - Auto-selection
    
    private func autoSelectDuplicatesForRemoval(in clusters: [DuplicateCluster]) {
        var toRemove = Set<UUID>()
        for cluster in clusters {
            // Find all members in this cluster that belong to the source folder (if configured)
            let sourceMemberIDs = cluster.members.compactMap { member -> UUID? in
                if let asset = assetsByID[member.assetID], isAssetInSourceFolder(asset) {
                    return member.assetID
                }
                return nil
            }
            
            if !sourceMemberIDs.isEmpty {
                // There are files from the source folder in this cluster:
                // 1. ALL files in the source folder are KEPT (never removed)
                // 2. All duplicate files OUTSIDE the source folder are marked for removal
                for member in cluster.members {
                    if !sourceMemberIDs.contains(member.assetID) {
                        toRemove.insert(member.assetID)
                    }
                }
            } else {
                // Default: Keep the recommended one, select other duplicates for removal
                let bestID = cluster.recommendedKeepID ?? cluster.members.first?.assetID
                for member in cluster.members {
                    if member.assetID != bestID {
                        toRemove.insert(member.assetID)
                    }
                }
            }
        }
        
        // Safety filter: make sure no asset in source folder is ever in toRemove
        toRemove = toRemove.filter { id in
            if let asset = assetsByID[id] {
                return !isAssetInSourceFolder(asset)
            }
            return true
        }
        
        self.selectedForRemoval = toRemove
    }
    
    // MARK: - Global Selection Actions
    
    public func autoSelectAllRecommended() {
        autoSelectDuplicatesForRemoval(in: clusters)
    }
    
    public func deselectAll() {
        selectedForRemoval.removeAll()
    }
    
    public func toggleRemoval(assetID: UUID) {
        if selectedForRemoval.contains(assetID) {
            selectedForRemoval.remove(assetID)
        } else {
            selectedForRemoval.insert(assetID)
        }
    }
    
    // MARK: - Cluster-level Selection Strategies
    
    public func setKeepOnly(cluster: DuplicateCluster, keepID: UUID) {
        for member in cluster.members {
            if member.assetID == keepID {
                selectedForRemoval.remove(member.assetID)
            } else {
                selectedForRemoval.insert(member.assetID)
            }
        }
    }
    
    public func invertClusterSelection(cluster: DuplicateCluster) {
        for member in cluster.members {
            if selectedForRemoval.contains(member.assetID) {
                selectedForRemoval.remove(member.assetID)
            } else {
                selectedForRemoval.insert(member.assetID)
            }
        }
    }
    
    public func resetClusterToSmartRecommendation(cluster: DuplicateCluster) {
        let bestID = cluster.recommendedKeepID ?? cluster.members.first?.assetID
        for member in cluster.members {
            if member.assetID == bestID {
                selectedForRemoval.remove(member.assetID)
            } else {
                selectedForRemoval.insert(member.assetID)
            }
        }
    }
    
    public func deselectAllInCluster(cluster: DuplicateCluster) {
        for member in cluster.members {
            selectedForRemoval.remove(member.assetID)
        }
    }
    
    // MARK: - Trash Execution
    
    public func trashSelectedFiles() async {
        guard !selectedForRemoval.isEmpty else { return }
        
        var trashedCount = 0
        var trashedBytes: Int64 = 0
        var failedFiles: [String] = []
        
        let idsToTrash = selectedForRemoval
        for assetID in idsToTrash {
            guard let asset = assetsByID[assetID] else { continue }
            do {
                try await fileActionEngine.trash(asset)
                trashedCount += 1
                trashedBytes += asset.fileIdentity.fileSize
                selectedForRemoval.remove(assetID)
            } catch {
                failedFiles.append(asset.path.lastPathComponent)
            }
        }
        
        // Remove trashed members from clusters
        var updatedClusters: [DuplicateCluster] = []
        for var cluster in clusters {
            cluster.members.removeAll { idsToTrash.contains($0.assetID) && !selectedForRemoval.contains($0.assetID) }
            if cluster.members.count > 1 {
                updatedClusters.append(cluster)
            }
        }
        self.clusters = updatedClusters
        if !updatedClusters.contains(where: { $0.id == selectedClusterID }) {
            selectedClusterID = updatedClusters.first?.id
        }
        
        let savedSizeStr = ByteCountFormatter.string(fromByteCount: trashedBytes, countStyle: .file)
        if failedFiles.isEmpty {
            self.statusToast = "Đã chuyển \(trashedCount) video vào Thùng rác (Giải phóng \(savedSizeStr))"
        } else {
            self.statusToast = "Đã chuyển \(trashedCount) video vào Thùng rác. Lỗi \(failedFiles.count) tệp."
        }
    }
    
    // MARK: - Cleanup on window close
    
    public func cleanup() {
        cancellables.removeAll()
        scanner?.cancelScan()
        scanner = nil
        clusters.removeAll()
        assetsByID.removeAll()
        selectedForRemoval.removeAll()
        activeDualComparison = nil
        Task {
            await VideoTwinThumbnailCache.shared.clear()
        }
    }
}

// MARK: - URL Volume & Storage Helpers

extension URL {
    public var isExternalVolume: Bool {
        if let values = try? resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsRemovableKey]) {
            if let isInternal = values.volumeIsInternal, !isInternal { return true }
            if let isRemovable = values.volumeIsRemovable, isRemovable { return true }
        }
        return path.hasPrefix("/Volumes/") && !path.hasPrefix("/Volumes/Macintosh HD")
    }
    
    public var volumeName: String {
        if let values = try? resourceValues(forKeys: [.volumeNameKey]), let name = values.volumeName, !name.isEmpty {
            return name
        }
        if path.hasPrefix("/Volumes/") {
            let components = path.components(separatedBy: "/")
            if components.count > 2 && !components[2].isEmpty {
                return components[2]
            }
        }
        return "Ổ máy"
    }
}
