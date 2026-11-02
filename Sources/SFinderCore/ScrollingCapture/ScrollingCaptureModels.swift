import Foundation
import CoreGraphics
import AppKit

public enum ScrollingCaptureMode: String, CaseIterable, Identifiable, Sendable {
    case autoScroll = "auto"
    case manualScroll = "manual"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .autoScroll: return "Tự động cuộn"
        case .manualScroll: return "Cuộn tay"
        }
    }
    
    public var icon: String {
        switch self {
        case .autoScroll: return "bolt.horizontal.fill"
        case .manualScroll: return "hand.draw.fill"
        }
    }
}

public enum ScrollingCaptureState: Equatable, Sendable {
    case idle
    case selecting
    case ready(CGRect)
    case capturing(ScrollingCaptureMode)
    case stitching
    case completed
    case error(String)
}

public struct ScrollingCaptureStats: Equatable, Sendable {
    public var frameCount: Int
    public var stitchedWidth: CGFloat
    public var stitchedHeight: CGFloat
    public var lastDisplacement: CGFloat
    public var duration: TimeInterval
    
    public init(
        frameCount: Int = 0,
        stitchedWidth: CGFloat = 0,
        stitchedHeight: CGFloat = 0,
        lastDisplacement: CGFloat = 0,
        duration: TimeInterval = 0
    ) {
        self.frameCount = frameCount
        self.stitchedWidth = stitchedWidth
        self.stitchedHeight = stitchedHeight
        self.lastDisplacement = lastDisplacement
        self.duration = duration
    }
    
    public var formattedDimensions: String {
        "\(Int(stitchedWidth)) × \(Int(stitchedHeight)) px"
    }
}
