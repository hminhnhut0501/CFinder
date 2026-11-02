import Foundation
import CoreGraphics
import AppKit

/// Bộ điều khiển tự động cuộn (Auto-Scroll Dispatcher)
/// Phát tín hiệu cuộn mượt mà trực tiếp vào tâm vùng được chọn bằng CoreGraphics CGEvent
public final class AutoScrollController: @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.sfinder.autoscroll", qos: .userInteractive)
    
    public private(set) var isRunning: Bool = false
    public private(set) var isPaused: Bool = false
    
    // Tốc độ cuộn: 2 dòng mỗi nhịp cuộn (tương đương 30-45px phù hợp với mọi ứng dụng macOS & trình duyệt)
    public var scrollStepLines: Int32 = 2
    // Khoảng thời gian giữa các bước (mặc định 80ms ~ 12.5 FPS cho mắt đọc & trình duyệt kịp vẽ lại)
    public var intervalMs: Int = 80
    
    private var targetPoint: CGPoint = .zero
    private var onStepCallback: (@Sendable () -> Void)?
    
    public init() {}
    
    /// Bắt đầu tự động cuộn tại toạ độ chỉ định (toạ độ Quartz Display)
    public func start(at point: CGPoint, onStep: @escaping @Sendable () -> Void) {
        stop()
        self.targetPoint = point
        self.onStepCallback = onStep
        self.isRunning = true
        self.isPaused = false
        
        // Di chuyển con trỏ chuột vào tâm vùng cuộn để kích hoạt cơ chế nhận sự kiện cuộn của macOS
        DispatchQueue.main.async {
            CGWarpMouseCursorPosition(point)
        }
        
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(intervalMs))
        newTimer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning, !self.isPaused else { return }
            self.dispatchScrollTick()
            self.onStepCallback?()
        }
        self.timer = newTimer
        newTimer.resume()
    }
    
    /// Tạm dừng cuộn
    public func pause() {
        isPaused = true
    }
    
    /// Tiếp tục cuộn
    public func resume() {
        isPaused = false
    }
    
    /// Dừng hẳn phiên tự cuộn
    public func stop() {
        isRunning = false
        isPaused = false
        timer?.cancel()
        timer = nil
        onStepCallback = nil
    }
    
    /// Phát 1 xung cuộn xuống (Scroll Down) vào vị trí mục tiêu
    private func dispatchScrollTick() {
        // Gửi xung cuộn đơn vị dòng (.line) tương thích tối đa với Safari, Chrome, Firefox, Arc, Finder, PDF Preview
        // wheel1: Giá trị âm (-scrollStepLines) là cuộn xuống
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: -scrollStepLines,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }
        
        scrollEvent.location = targetPoint
        scrollEvent.post(tap: .cghidEventTap)
    }
}
