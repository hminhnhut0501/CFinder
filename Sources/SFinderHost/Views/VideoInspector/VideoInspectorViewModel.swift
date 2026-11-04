import SwiftUI
import AppKit
import SFinderCore

@MainActor
public final class VideoInspectorViewModel: ObservableObject {
    public let urls: [URL]
    
    @Published public private(set) var reports: [VideoDetailedReport] = []
    @Published public private(set) var isLoading: Bool = true
    @Published public private(set) var errorMessage: String? = nil
    @Published public var selectedTab: Int = 0
    @Published public var comparisonVerdict: ComparisonVerdict? = nil
    @Published public var statusToast: String? = nil
    
    // For launching dual player modal if available
    @Published public var activeDualComparison: (URL, URL)? = nil
    
    private let engine = VideoInspectorEngine.shared
    private let scorer = VideoScoringEngine()
    
    public init(urls: [URL]) {
        self.urls = urls
    }
    
    public func loadReports() {
        isLoading = true
        errorMessage = nil
        
        Task {
            let loaded = await engine.inspectBatch(urls: urls)
            if loaded.isEmpty {
                self.errorMessage = "Không thể phân tích định dạng các video đã chọn."
            } else {
                self.reports = loaded
                if loaded.count >= 2 {
                    self.comparisonVerdict = scorer.compareVideos(reports: loaded)
                }
            }
            self.isLoading = false
        }
    }
    
    public func keepOnly(winnerURL: URL) async {
        let others = reports.filter { $0.url != winnerURL }
        var trashedCount = 0
        var trashedBytes: Int64 = 0
        
        for rep in others {
            do {
                try FileManager.default.trashItem(at: rep.url, resultingItemURL: nil)
                trashedCount += 1
                trashedBytes += rep.fileSize
            } catch {
                NSLog("[VideoInspector] Failed to trash \(rep.url): \(error)")
            }
        }
        
        let sizeStr = ByteCountFormatter.string(fromByteCount: trashedBytes, countStyle: .file)
        self.statusToast = "Đã dọn \(trashedCount) video vào Thùng rác (Giải phóng \(sizeStr))"
        
        // Reload remaining
        self.reports = self.reports.filter { $0.url == winnerURL }
        self.comparisonVerdict = nil
    }
    
    public func trashSingle(url: URL) async {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            self.reports.removeAll { $0.url == url }
            if self.reports.count >= 2 {
                self.comparisonVerdict = scorer.compareVideos(reports: self.reports)
            } else {
                self.comparisonVerdict = nil
            }
            self.statusToast = "Đã chuyển vào Thùng rác"
        } catch {
            self.statusToast = "Lỗi khi xóa: \(error.localizedDescription)"
        }
    }
}
