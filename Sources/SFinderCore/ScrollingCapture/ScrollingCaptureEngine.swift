import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit
import AudioToolbox

/// Trình điều phối Chụp cuộn toàn diện của SFinder
/// Hỗ trợ cả 2 chế độ: Tự động cuộn (Auto-Scroll) và Cuộn tay (Manual Scroll)
@MainActor
public final class ScrollingCaptureEngine: ObservableObject {
    public static let shared = ScrollingCaptureEngine()
    
    // MARK: - Published State
    @Published public private(set) var state: ScrollingCaptureState = .idle
    @Published public var currentMode: ScrollingCaptureMode = .autoScroll
    @Published public private(set) var stats: ScrollingCaptureStats = ScrollingCaptureStats()
    @Published public private(set) var currentPreviewThumbnail: NSImage?
    @Published public private(set) var finalStitchedImage: NSImage?
    
    // Callbacks
    public var onStateChanged: ((ScrollingCaptureState) -> Void)?
    public var onFinished: ((NSImage) -> Void)?
    public var onCancel: (() -> Void)?
    public var onShowToast: ((String, String, String) -> Void)?
    
    // Internal Components
    private let stitcher = ImageStitcher()
    private let autoScroller = AutoScrollController()
    
    // Active Session Data
    public private(set) var captureRect: CGRect = .zero
    private var captureTimer: Timer?
    private var consecutiveStaticFrames: Int = 0
    private var sessionStartTime: Date = Date()
    private var isCapturingLoop: Bool = false
    
    private init() {}
    
    // MARK: - Session Lifecycle
    
    /// Bắt đầu phiên chụp cuộn: chuyển sang trạng thái chọn vùng màn hình
    public func startSelection() {
        reset()
        self.state = .selecting
        onStateChanged?(.selecting)
    }
    
    /// Xác nhận vùng màn hình đã chọn
    /// - Parameter rect: Vùng toạ độ màn hình (Cocoa / Global screen bounds)
    public func setTargetRect(_ rect: CGRect) {
        guard rect.width >= 100 && rect.height >= 100 else {
            cancelSession()
            return
        }
        
        self.captureRect = rect
        self.state = .ready(rect)
        onStateChanged?(.ready(rect))
        
        // Chụp khung hình gốc đầu tiên ngay lập tức
        Task {
            if let initial = await captureViewportImage() {
                stitcher.start(with: initial)
                updateStatsAndThumbnail()
            }
        }
    }
    
    /// Bắt đầu chụp theo chế độ hiện tại (.autoScroll hoặc .manualScroll)
    public func startCapturing() {
        guard case .ready = state else { return }
        
        self.state = .capturing(currentMode)
        self.sessionStartTime = Date()
        self.consecutiveStaticFrames = 0
        onStateChanged?(.capturing(currentMode))
        
        switch currentMode {
        case .autoScroll:
            startAutoScrollMode()
        case .manualScroll:
            startManualScrollMode()
        }
    }
    
    /// Tạm dừng hoặc tiếp tục khi đang ở chế độ tự động cuộn
    public func toggleAutoScrollPause() {
        if autoScroller.isPaused {
            autoScroller.resume()
        } else {
            autoScroller.pause()
        }
    }
    
    public var isAutoScrollPaused: Bool {
        autoScroller.isPaused
    }
    
    /// Hoàn tất chụp cuộn và xuất ảnh dài hoàn chỉnh
    public func finishCapture() {
        stopAllLoops()
        self.state = .stitching
        onStateChanged?(.stitching)
        
        guard let finalCG = stitcher.compositeImage else {
            cancelSession()
            return
        }
        
        let finalImage = NSImage(cgImage: finalCG, size: NSSize(width: finalCG.width, height: finalCG.height))
        self.finalStitchedImage = finalImage
        self.state = .completed
        onStateChanged?(.completed)
        
        // 1. Tự động sao chép ngay vào Clipboard hệ thống
        copyImageToClipboard(finalImage)
        
        // 2. Phát âm thanh chụp màn hình chuyên nghiệp
        AudioServicesPlaySystemSound(1108)
        
        // 3. Thông báo hoàn tất
        onShowToast?("camera.fill", "Đã chụp cuộn thành công!", "Ảnh dài \(finalCG.width)×\(finalCG.height) px đã được sao chép vào Clipboard")
        onFinished?(finalImage)
    }
    
    /// Huỷ phiên chụp
    public func cancelSession() {
        stopAllLoops()
        reset()
        self.state = .idle
        onStateChanged?(.idle)
        onCancel?()
    }
    
    private func reset() {
        stitcher.reset()
        autoScroller.stop()
        captureTimer?.invalidate()
        captureTimer = nil
        captureRect = .zero
        stats = ScrollingCaptureStats()
        currentPreviewThumbnail = nil
        finalStitchedImage = nil
        consecutiveStaticFrames = 0
        isCapturingLoop = false
    }
    
    private func stopAllLoops() {
        autoScroller.stop()
        captureTimer?.invalidate()
        captureTimer = nil
        isCapturingLoop = false
    }
    
    // MARK: - Capture Loops
    
    private func startAutoScrollMode() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        // Chuyển toạ độ tâm từ Cocoa Screen (gốc đáy-trái) sang Quartz Display (gốc trên-trái)
        let quartzCenterPoint = CGPoint(
            x: captureRect.midX,
            y: primaryHeight - captureRect.midY
        )
        
        // Chạy vòng lặp tự cuộn và chụp
        autoScroller.start(at: quartzCenterPoint) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, case .capturing = self.state else { return }
                await self.tickCapture()
            }
        }
    }
    
    private func startManualScrollMode() {
        // Ở chế độ cuộn tay: Thiết lập timer lấy mẫu tốc độ 12 FPS để liên tục đón các lát cuộn của người dùng
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, case .capturing = self.state else { return }
                await self.tickCapture()
            }
        }
    }
    
    /// Nhịp lấy mẫu và ghép ảnh
    private func tickCapture() async {
        guard !isCapturingLoop else { return }
        isCapturingLoop = true
        defer { isCapturingLoop = false }
        
        guard let frame = await captureViewportImage() else { return }
        
        let (_, dy, isNew) = stitcher.appendFrame(frame)
        
        if isNew && dy > 0 {
            consecutiveStaticFrames = 0
            stats.lastDisplacement = dy
            updateStatsAndThumbnail()
        } else {
            consecutiveStaticFrames += 1
            
            let elapsed = Date().timeIntervalSince(sessionStartTime)
            // Chỉ kết thúc tự động nếu:
            // 1. Đã ghép thành công ít nhất 3 khung hình
            // 2. Đã trôi qua ít nhất 2.5 giây từ lúc nhấn bắt đầu
            // 3. Số khung hình tĩnh liên tiếp >= 20 (~1.6 giây trang hoàn toàn không di chuyển thêm)
            if currentMode == .autoScroll {
                if stitcher.frameCount >= 3 && elapsed >= 2.5 && consecutiveStaticFrames >= 20 {
                    finishCapture()
                } else if stitcher.frameCount < 3 && elapsed >= 8.0 && consecutiveStaticFrames >= 60 {
                    // Dự phòng trường hợp nội dung trang hoàn toàn không thể cuộn
                    finishCapture()
                }
            }
        }
    }
    
    private func updateStatsAndThumbnail() {
        guard let comp = stitcher.compositeImage else { return }
        
        stats.frameCount = stitcher.frameCount
        stats.stitchedWidth = CGFloat(comp.width)
        stats.stitchedHeight = CGFloat(comp.height)
        stats.duration = Date().timeIntervalSince(sessionStartTime)
        
        // Tạo ảnh thumbnail nhỏ tỉ lệ chính xác cho HUD
        let thumbW: CGFloat = 80
        let thumbH = max(100, min(180, thumbW * (CGFloat(comp.height) / max(1, CGFloat(comp.width)))))
        let thumb = NSImage(cgImage: comp, size: NSSize(width: thumbW, height: thumbH))
        self.currentPreviewThumbnail = thumb
    }
    
    // MARK: - Viewport Screen Capture
    
    /// Chụp ảnh khu vực viewport bằng ScreenCaptureKit (với fallback screencapture)
    public func captureViewportImage() async -> CGImage? {
        guard captureRect.width > 0 && captureRect.height > 0 else { return nil }
        
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        // Chuyển đổi vùng chọn từ toạ độ Cocoa (gốc dưới-trái) sang toạ độ Quartz Display (gốc trên-trái)
        let quartzRect = CGRect(
            x: captureRect.minX,
            y: primaryHeight - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )
        
        // 1. Thử chụp bằng ScreenCaptureKit (cực nhanh, in-memory)
        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                // Tìm display chứa quartzRect
                let targetDisplay = content.displays.first(where: {
                    let dispFrame = CGRect(x: CGFloat($0.frame.origin.x), y: CGFloat($0.frame.origin.y), width: CGFloat($0.width), height: CGFloat($0.height))
                    return dispFrame.intersects(quartzRect)
                }) ?? content.displays.first
                
                if let display = targetDisplay {
                    let myPID = ProcessInfo.processInfo.processIdentifier
                    let myWindows = content.windows.filter { $0.owningApplication?.processID == myPID }
                    let filter = SCContentFilter(display: display, excludingWindows: myWindows)
                    
                    let config = SCStreamConfiguration()
                    let dispOrigin = display.frame.origin
                    config.sourceRect = CGRect(
                        x: quartzRect.minX - CGFloat(dispOrigin.x),
                        y: quartzRect.minY - CGFloat(dispOrigin.y),
                        width: quartzRect.width,
                        height: quartzRect.height
                    )
                    config.width = Int(quartzRect.width * 2)
                    config.height = Int(quartzRect.height * 2)
                    config.scalesToFit = false
                    config.showsCursor = false
                    
                    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    return cgImage
                }
            } catch {
                // Tiếp tục fallback
            }
        }
        
        // 2. Fallback: /usr/sbin/screencapture CLI
        return captureWithCLI(rect: captureRect)
    }
    
    private func captureWithCLI(rect: CGRect) -> CGImage? {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sfinder_scroll_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        let cliY = Int(primaryHeight - rect.maxY)
        let cliX = Int(rect.minX)
        let cliW = Int(rect.width)
        let cliH = Int(rect.height)
        
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-R", "\(cliX),\(cliY),\(cliW),\(cliH)", "-x", tempURL.path]
        
        try? p.run()
        p.waitUntilExit()
        
        guard let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return img
    }
    
    // MARK: - Pasteboard Utility
    
    private func copyImageToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
