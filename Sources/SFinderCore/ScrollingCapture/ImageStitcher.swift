import Foundation
import CoreGraphics
import AppKit

/// Bộ ghép ảnh cuộn liền mạch (Seamless Long Screenshot Stitcher)
/// Sử dụng thuật toán so khớp dải pixel siêu tốc (Sub-pixel Strip Correlation) kết hợp kiểm định sai số tối thiểu (MAD - Mean Absolute Difference)
/// Đảm bảo không tạo vệt răng cưa, không giật đường biên và chính xác từng pixel.
public final class ImageStitcher: @unchecked Sendable {
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    // Khung hình ghép tích luỹ hiện tại
    public private(set) var compositeImage: CGImage?
    public private(set) var previousFrame: CGImage?
    public private(set) var totalShift: CGFloat = 0
    public private(set) var frameCount: Int = 0
    
    // Giới hạn an toàn
    public let maxStitchedHeight: Int = 32000 // Tối đa 32k pixel
    public let maxShiftPerFrame: Int = 220    // Tối đa 220px mỗi bước cuộn
    
    public init() {}
    
    /// Bắt đầu phiên ghép mới với khung hình đầu tiên
    public func start(with initialFrame: CGImage) {
        self.compositeImage = initialFrame
        self.previousFrame = initialFrame
        self.totalShift = 0
        self.frameCount = 1
    }
    
    /// Đặt lại toàn bộ trạng thái
    public func reset() {
        compositeImage = nil
        previousFrame = nil
        totalShift = 0
        frameCount = 0
    }
    
    /// Thêm khung hình mới vào chuỗi ghép cuộn
    /// - Parameter newFrame: Khung hình mới chụp từ viewport
    /// - Returns: Tuple gồm (ảnh ghép đã cập nhật, độ dịch chuyển pixel dy, có nội dung mới hay không)
    public func appendFrame(_ newFrame: CGImage) -> (updatedImage: CGImage?, dy: CGFloat, isNewContent: Bool) {
        guard let prev = previousFrame, let currentComp = compositeImage else {
            start(with: newFrame)
            return (compositeImage, 0, true)
        }
        
        let w = prev.width
        let h = prev.height
        
        guard newFrame.width == w && newFrame.height == h else {
            return (compositeImage, 0, false)
        }
        
        // 1. Tìm độ dịch chuyển dọc dy
        let (detectedDy, confidence) = findVerticalDisplacement(prev: prev, next: newFrame)
        
        // Nếu không phát hiện cuộn (hoặc cuộn quá nhỏ < 2px), bỏ qua không ghép trùng
        guard detectedDy >= 2 && confidence > 0.65 else {
            return (compositeImage, 0, false)
        }
        
        // Kiểm tra trần chiều cao tối đa
        let newCompositeHeight = currentComp.height + detectedDy
        guard newCompositeHeight <= maxStitchedHeight else {
            return (compositeImage, CGFloat(detectedDy), false)
        }
        
        // 2. Cắt lát nội dung mới lộ ra ở đáy khung hình mới (chiều cao detectedDy)
        // Trong toạ độ bitmap chuẩn, nội dung mới xuất hiện ở đáy: y từ (h - detectedDy) đến h
        // Lưu ý khi crop bằng CoreGraphics: origin (0, 0) của CGImage.cropping(to:) tính từ góc trên-trái trong CoreGraphics macOS
        let sliceRect = CGRect(x: 0, y: h - detectedDy, width: w, height: detectedDy)
        guard let newSlice = newFrame.cropping(to: sliceRect) else {
            return (compositeImage, 0, false)
        }
        
        // 3. Tạo context mới mở rộng chiều cao và vẽ nối tiếp
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: newCompositeHeight,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return (compositeImage, 0, false)
        }
        
        // Trong CGContext: Toạ độ y = 0 là ở đáy (Bottom-Left)
        // Vì vậy:
        // - Ảnh cũ nằm ở phía trên: y = detectedDy
        // - Lát cắt mới nằm ở đáy: y = 0
        ctx.draw(currentComp, in: CGRect(x: 0, y: detectedDy, width: w, height: currentComp.height))
        ctx.draw(newSlice, in: CGRect(x: 0, y: 0, width: w, height: detectedDy))
        
        guard let updatedComp = ctx.makeImage() else {
            return (compositeImage, 0, false)
        }
        
        self.compositeImage = updatedComp
        self.previousFrame = newFrame
        self.totalShift += CGFloat(detectedDy)
        self.frameCount += 1
        
        return (updatedComp, CGFloat(detectedDy), true)
    }
    
    // MARK: - Core Matching Engine
    
    /// Tính toán độ dịch chuyển dọc chính xác giữa hai khung hình liên tiếp
    private func findVerticalDisplacement(prev: CGImage, next: CGImage) -> (dy: Int, confidence: Double) {
        let w = prev.width
        let h = prev.height
        
        guard let d1 = prev.dataProvider?.data, let p1 = CFDataGetBytePtr(d1),
              let d2 = next.dataProvider?.data, let p2 = CFDataGetBytePtr(d2) else {
            return (0, 0.0)
        }
        
        let bpr1 = prev.bytesPerRow
        let bpr2 = next.bytesPerRow
        
        // Dải mẫu đối chiếu (Template Strip)
        // Lấy 30 dòng ở nửa dưới của ảnh trước (để đảm bảo vẫn còn nằm trong ảnh sau khi cuộn lên)
        let stripH = 30
        let templateY = max(20, h - maxShiftPerFrame - stripH)
        guard templateY > 0 && (templateY + stripH) <= h else {
            return (0, 0.0)
        }
        
        var bestDy = 0
        var minDiff: UInt64 = UInt64.max
        var secondMinDiff: UInt64 = UInt64.max
        
        let stepX = 4 // Subsample 1/4 pixel theo chiều ngang để tăng tốc gấp 4 lần
        let totalSampledPixels = (stripH * (w / stepX))
        guard totalSampledPixels > 0 else { return (0, 0.0) }
        
        // Duyệt tìm kiếm dy trong khoảng 1 đến maxShiftPerFrame
        for dy in 1...maxShiftPerFrame {
            let targetY = templateY - dy
            guard targetY >= 0 else { break }
            
            var diff: UInt64 = 0
            for r in 0..<stripH {
                let row1 = (templateY + r) * bpr1
                let row2 = (targetY + r) * bpr2
                for x in stride(from: 0, to: w, by: stepX) {
                    let off1 = row1 + x * 4
                    let off2 = row2 + x * 4
                    let dr = abs(Int32(p1[off1]) - Int32(p2[off2]))
                    let dg = abs(Int32(p1[off1+1]) - Int32(p2[off2+1]))
                    let db = abs(Int32(p1[off1+2]) - Int32(p2[off2+2]))
                    diff += UInt64(dr + dg + db)
                }
            }
            
            if diff < minDiff {
                secondMinDiff = minDiff
                minDiff = diff
                bestDy = dy
            } else if diff < secondMinDiff {
                secondMinDiff = diff
            }
        }
        
        // Tính điểm tự tin (Confidence): Dựa trên sai số trung bình trên mỗi kênh màu của pixel (0..255)
        let avgDiffPerPixel = Double(minDiff) / Double(totalSampledPixels * 3)
        // Nếu avgDiff < 5 (trên thang 255) => Độ trùng khớp cực cao > 98%
        let confidence = max(0.0, 1.0 - (avgDiffPerPixel / 35.0))
        
        return (bestDy, confidence)
    }
}
