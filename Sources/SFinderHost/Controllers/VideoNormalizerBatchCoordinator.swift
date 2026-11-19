import Foundation
import AppKit
import SwiftUI
import OSLog
import SFinderCore

@MainActor
public final class VideoNormalizerBatchCoordinator: ObservableObject {
    public static let shared = VideoNormalizerBatchCoordinator()
    private let logger = Logger(subsystem: "com.sfinder.host", category: "VideoNormalizerBatchCoordinator")
    
    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "ts", "flv", "wmv", "3gp", "m2ts"
    ]
    
    @Published public private(set) var isProcessing: Bool = false
    @Published public private(set) var isCompleted: Bool = false
    @Published public private(set) var currentFileIndex: Int = 0
    @Published public private(set) var totalFilesCount: Int = 0
    @Published public private(set) var currentFileName: String = ""
    @Published public private(set) var currentStrategyDesc: String = ""
    @Published public private(set) var currentProgress: Double = 0.0
    @Published public private(set) var currentSpeed: Double = 0.0
    @Published public private(set) var currentFPS: Double = 0.0
    @Published public private(set) var currentETA: Double? = nil
    @Published public private(set) var totalSavedBytes: Int64 = 0
    @Published public private(set) var completionSummary: String = ""
    @Published public private(set) var lastOutputDir: URL? = nil
    @Published public private(set) var lastOutputFileURL: URL? = nil
    
    private var activeProcessingTask: Task<Void, Never>?
    private var isCancelled: Bool = false
    
    private init() {}
    
    // MARK: - Batch Dispatch Entrypoint
    
    public func startBatch(urls: [URL]) {
        let videoURLs = resolveVideoFiles(from: urls)
        
        guard !videoURLs.isEmpty else {
            FloatingHUDController.shared.showToast(
                icon: "exclamationmark.triangle.fill",
                iconColor: .orange,
                title: "Không tìm thấy video",
                subtitle: "Vui lòng chọn tệp video hợp lệ (.mp4, .mov, .mkv, .avi, .webm...)",
                duration: 3.0
            )
            return
        }
        
        if isProcessing {
            FloatingHUDController.shared.showToast(
                icon: "hourglass",
                iconColor: .yellow,
                title: "Đang có tiến trình xử lý",
                subtitle: "Vui lòng đợi tác vụ hiện tại hoàn tất hoặc huỷ trước.",
                duration: 3.0
            )
            return
        }
        
        isProcessing = true
        isCompleted = false
        isCancelled = false
        currentFileIndex = 0
        totalFilesCount = videoURLs.count
        currentProgress = 0.0
        currentSpeed = 0.0
        currentFPS = 0.0
        currentETA = nil
        totalSavedBytes = 0
        completionSummary = ""
        lastOutputDir = videoURLs.first?.deletingLastPathComponent()
        
        // Show Floating Progress HUD
        VideoNormalizerHUDController.shared.show()
        
        activeProcessingTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.processQueue(videoURLs)
        }
    }
    
    public func cancel() {
        isCancelled = true
        activeProcessingTask?.cancel()
        activeProcessingTask = nil
        isProcessing = false
        isCompleted = false
        
        VideoNormalizerHUDController.shared.hide(animated: true)
        
        FloatingHUDController.shared.showToast(
            icon: "xmark.circle.fill",
            iconColor: .red,
            title: "Đã huỷ chuẩn hoá video",
            subtitle: "Các tác vụ đang chạy đã dừng lại an toàn.",
            duration: 2.5
        )
    }
    
    // MARK: - Queue Processing
    
    nonisolated private func processQueue(_ urls: [URL]) async {
        var successCount = 0
        var alreadyOptimalCount = 0
        var accumulatedSavedBytes: Int64 = 0
        var errors: [(URL, String)] = []
        var lastCompletedFile: URL?
        
        let startTime = Date()
        
        for (index, fileURL) in urls.enumerated() {
            let isCancelled = await MainActor.run { self.isCancelled }
            if isCancelled { break }
            
            // Analyze strategy upfront for instant HUD feedback
            let plan = try? await VideoNormalizerEngine.shared.analyze(fileURL: fileURL)
            let strategyBadge: String
            if let p = plan {
                switch p.strategy {
                case .alreadyOptimal:
                    strategyBadge = "Đã tối ưu ✨"
                case .remuxFastStart:
                    strategyBadge = "Fast Remux ⚡"
                case .transcode:
                    strategyBadge = p.encoder.contains("videotoolbox") ? "VideoToolbox 🚀" : "CPU libx264 ⚙️"
                }
            } else {
                strategyBadge = "Đang xử lý..."
            }
            
            await MainActor.run {
                self.currentFileIndex = index + 1
                self.currentFileName = fileURL.lastPathComponent
                self.currentStrategyDesc = strategyBadge
                self.currentProgress = 0.0
                self.currentSpeed = 0.0
                self.currentFPS = 0.0
                self.currentETA = nil
            }
            
            do {
                let result = try await VideoNormalizerEngine.shared.normalize(fileURL: fileURL) { [weak self] progress in
                    Task { @MainActor in
                        guard let self = self, !self.isCancelled else { return }
                        self.currentProgress = progress.progressRatio
                        self.currentSpeed = progress.speed
                        self.currentFPS = progress.fps
                        self.currentETA = progress.etaSeconds
                    }
                }
                
                lastCompletedFile = result.destinationURL
                
                if result.wasAlreadyOptimal {
                    alreadyOptimalCount += 1
                } else {
                    successCount += 1
                }
                
                let saved = max(0, result.verification.savedBytes)
                accumulatedSavedBytes += saved
                
                await MainActor.run {
                    self.currentProgress = 1.0
                    self.totalSavedBytes = accumulatedSavedBytes
                    self.lastOutputFileURL = result.destinationURL
                    self.lastOutputDir = result.destinationURL.deletingLastPathComponent()
                }
            } catch {
                self.logger.error("Failed to normalize \(fileURL.lastPathComponent): \(error.localizedDescription)")
                errors.append((fileURL, error.localizedDescription))
            }
        }
        
        let totalElapsed = Date().timeIntervalSince(startTime)
        
        await MainActor.run {
            self.isProcessing = false
            self.activeProcessingTask = nil
            
            if self.isCancelled {
                return
            }
            
            self.notifyBatchComplete(
                totalCount: urls.count,
                successCount: successCount,
                alreadyOptimalCount: alreadyOptimalCount,
                savedBytes: accumulatedSavedBytes,
                elapsedSeconds: totalElapsed,
                lastFileURL: lastCompletedFile,
                errors: errors
            )
        }
    }
    
    // MARK: - Completion Notification
    
    private func notifyBatchComplete(
        totalCount: Int,
        successCount: Int,
        alreadyOptimalCount: Int,
        savedBytes: Int64,
        elapsedSeconds: TimeInterval,
        lastFileURL: URL?,
        errors: [(URL, String)]
    ) {
        let savedMB = Double(savedBytes) / (1024.0 * 1024.0)
        let timeDesc = String(format: "%.1f", elapsedSeconds)
        
        let summaryText: String
        if errors.isEmpty {
            if totalCount == 1 {
                if alreadyOptimalCount == 1 {
                    summaryText = "Chuẩn stream tối ưu (Fast Remux • \(timeDesc)s)"
                } else if savedMB > 0.5 {
                    summaryText = "Hoàn tất! Tiết kiệm \(String(format: "%.1f", savedMB)) MB (\(timeDesc)s)"
                } else {
                    summaryText = "Hoàn tất trong \(timeDesc)s • Sẵn sàng phát stream"
                }
            } else {
                if alreadyOptimalCount == totalCount {
                    summaryText = "Tất cả \(totalCount) video đã đạt chuẩn tối ưu stream (\(timeDesc)s)"
                } else if savedMB > 0.5 {
                    summaryText = "Xong \(successCount + alreadyOptimalCount)/\(totalCount) video trong \(timeDesc)s • Giảm \(String(format: "%.1f", savedMB)) MB"
                } else {
                    summaryText = "Xong \(successCount + alreadyOptimalCount)/\(totalCount) video trong \(timeDesc)s • Sẵn sàng phát"
                }
            }
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.completionSummary = summaryText
                self.isCompleted = true
                self.currentProgress = 1.0
                if let file = lastFileURL {
                    self.lastOutputFileURL = file
                    self.lastOutputDir = file.deletingLastPathComponent()
                }
            }
            
            // Audio cue
            NSSound(named: "Glass")?.play()
            
            // Auto-dismiss HUD after 6 seconds
            VideoNormalizerHUDController.shared.scheduleAutoDismiss(after: 6.0)
        } else {
            let errorMsg = errors.first?.1 ?? "Lỗi xử lý file"
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.completionSummary = "Lỗi \(errors.count)/\(totalCount) tệp: \(errorMsg)"
                self.isCompleted = true
            }
            
            VideoNormalizerHUDController.shared.scheduleAutoDismiss(after: 8.0)
        }
    }
    
    // MARK: - URL Resolution Helper
    
    private func resolveVideoFiles(from urls: [URL]) -> [URL] {
        var results: [URL] = []
        var visited = Set<String>()
        let fm = FileManager.default
        
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    // Directory: scan items inside
                    if let enumerator = fm.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) {
                        for case let itemURL as URL in enumerator {
                            let ext = itemURL.pathExtension.lowercased()
                            let base = itemURL.deletingPathExtension().lastPathComponent
                            if Self.videoExtensions.contains(ext) && !base.hasSuffix("_stream") && !visited.contains(itemURL.path) {
                                visited.insert(itemURL.path)
                                results.append(itemURL)
                            }
                        }
                    }
                } else {
                    // Regular file
                    let ext = url.pathExtension.lowercased()
                    if Self.videoExtensions.contains(ext) && !visited.contains(url.path) {
                        visited.insert(url.path)
                        results.append(url)
                    }
                }
            }
        }
        
        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
