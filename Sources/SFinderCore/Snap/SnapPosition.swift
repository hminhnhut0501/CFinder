import Foundation
import AppKit

public enum SnapPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case maximize = "maximize"
    case leftHalf = "left_half"
    case rightHalf = "right_half"
    case topHalf = "top_half"
    case bottomHalf = "bottom_half"
    case topLeft = "top_left"
    case topRight = "top_right"
    case bottomLeft = "bottom_left"
    case bottomRight = "bottom_right"
    case center = "center"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .maximize: return "Toàn màn hình"
        case .leftHalf: return "Chia đôi: Bên trái (50%)"
        case .rightHalf: return "Chia đôi: Bên phải (50%)"
        case .topHalf: return "Chia đôi: Nửa trên (50%)"
        case .bottomHalf: return "Chia đôi: Nửa dưới (50%)"
        case .topLeft: return "Chia tư: Góc trên trái (25%)"
        case .topRight: return "Chia tư: Góc trên phải (25%)"
        case .bottomLeft: return "Chia tư: Góc dưới trái (25%)"
        case .bottomRight: return "Chia tư: Góc dưới phải (25%)"
        case .center: return "Căn giữa màn hình"
        }
    }
    
    public var shortcutLabel: String {
        switch self {
        case .maximize: return "⌃⌥↑"
        case .leftHalf: return "⌃⌥←"
        case .rightHalf: return "⌃⌥→"
        case .topHalf: return "⌃⌥T"
        case .bottomHalf: return "⌃⌥B"
        case .topLeft: return "⌃⌥U"
        case .topRight: return "⌃⌥I"
        case .bottomLeft: return "⌃⌥J"
        case .bottomRight: return "⌃⌥K"
        case .center: return "⌃⌥C"
        }
    }
    
    public var icon: String {
        switch self {
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeft: return "rectangle.split.2x2"
        case .topRight: return "rectangle.split.2x2"
        case .bottomLeft: return "rectangle.split.2x2"
        case .bottomRight: return "rectangle.split.2x2"
        case .center: return "viewfinder"
        }
    }
    
    /// Calculate Cocoa frame for this position on given screen with custom gaps
    public func frame(on screen: NSScreen, gap: CGFloat = 0) -> CGRect {
        let vis = screen.visibleFrame
        let g = max(0, gap)
        
        switch self {
        case .maximize:
            return CGRect(
                x: vis.minX + g,
                y: vis.minY + g,
                width: max(200, vis.width - (g * 2)),
                height: max(200, vis.height - (g * 2))
            )
            
        case .leftHalf:
            let w = (vis.width - (g * 3)) / 2
            return CGRect(
                x: vis.minX + g,
                y: vis.minY + g,
                width: max(200, w),
                height: max(200, vis.height - (g * 2))
            )
            
        case .rightHalf:
            let w = (vis.width - (g * 3)) / 2
            return CGRect(
                x: vis.minX + g + w + g,
                y: vis.minY + g,
                width: max(200, w),
                height: max(200, vis.height - (g * 2))
            )
            
        case .topHalf:
            let h = (vis.height - (g * 3)) / 2
            return CGRect(
                x: vis.minX + g,
                y: vis.minY + g + h + g,
                width: max(200, vis.width - (g * 2)),
                height: max(200, h)
            )
            
        case .bottomHalf:
            let h = (vis.height - (g * 3)) / 2
            return CGRect(
                x: vis.minX + g,
                y: vis.minY + g,
                width: max(200, vis.width - (g * 2)),
                height: max(200, h)
            )
            
        case .topLeft:
            let w = (vis.width - (g * 3)) / 2
            let h = (vis.height - (g * 3)) / 2
            return CGRect(
                x: vis.minX + g,
                y: vis.minY + g + h + g,
                width: max(200, w),
                height: max(200, h)
            )
            
        case .topRight:
            let w = (vis.width - (g * 3)) / 2
            let h = (vis.height - (g * 3)) / 2
            return CGRect(
                x: vis.minX + g + w + g,
                y: vis.minY + g + h + g,
                width: max(200, w),
                height: max(200, h)
            )
            
        case .bottomLeft:
            let w = (vis.width - (g * 3)) / 2
            let h = (vis.height - (g * 3)) / 2
            return CGRect(
                x: vis.minX + g,
                y: vis.minY + g,
                width: max(200, w),
                height: max(200, h)
            )
            
        case .bottomRight:
            let w = (vis.width - (g * 3)) / 2
            let h = (vis.height - (g * 3)) / 2
            return CGRect(
                x: vis.minX + g + w + g,
                y: vis.minY + g,
                width: max(200, w),
                height: max(200, h)
            )
            
        case .center:
            let w = vis.width * 0.72
            let h = vis.height * 0.76
            return CGRect(
                x: vis.minX + (vis.width - w) / 2,
                y: vis.minY + (vis.height - h) / 2,
                width: max(200, w),
                height: max(200, h)
            )
        }
    }
    
    /// Converts a Cocoa screen coordinate rectangle to Accessibility API (Quartz) coordinates
    public static func toAXFrame(_ cocoaRect: CGRect, primaryScreenHeight: CGFloat) -> (origin: CGPoint, size: CGSize) {
        let axX = cocoaRect.minX
        let axY = primaryScreenHeight - cocoaRect.maxY
        return (CGPoint(x: axX, y: axY), CGSize(width: cocoaRect.width, height: cocoaRect.height))
    }
}
