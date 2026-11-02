import Foundation
import AppKit

public struct ScreenSnapConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: String { screenKey }
    
    public var screenKey: String
    public var displayName: String
    public var windowGap: CGFloat
    public var enableTopMaximize: Bool
    public var enableSideHalves: Bool
    public var enableCorners: Bool
    public var enableBottomHalf: Bool
    public var edgeSensitivity: CGFloat
    public var cornerSensitivity: CGFloat
    
    public init(
        screenKey: String,
        displayName: String,
        windowGap: CGFloat = 6.0,
        enableTopMaximize: Bool = true,
        enableSideHalves: Bool = true,
        enableCorners: Bool = true,
        enableBottomHalf: Bool = true,
        edgeSensitivity: CGFloat = 18.0,
        cornerSensitivity: CGFloat = 42.0
    ) {
        self.screenKey = screenKey
        self.displayName = displayName
        self.windowGap = windowGap
        self.enableTopMaximize = enableTopMaximize
        self.enableSideHalves = enableSideHalves
        self.enableCorners = enableCorners
        self.enableBottomHalf = enableBottomHalf
        self.edgeSensitivity = edgeSensitivity
        self.cornerSensitivity = cornerSensitivity
    }
    
    public static func `default`(for screen: NSScreen, index: Int) -> ScreenSnapConfig {
        let name = screen.localizedName.isEmpty ? "Màn hình \(index + 1)" : screen.localizedName
        let isBuiltIn = screen.localizedName.contains("Built-in") || index == 0
        let displayLabel = isBuiltIn ? "\(name) (Chính)" : name
        let key = "screen_\(Int(screen.frame.width))x\(Int(screen.frame.height))_\(index)"
        
        return ScreenSnapConfig(
            screenKey: key,
            displayName: displayLabel,
            windowGap: 6.0,
            enableTopMaximize: true,
            enableSideHalves: true,
            enableCorners: true,
            enableBottomHalf: true,
            edgeSensitivity: 18.0,
            cornerSensitivity: 42.0
        )
    }
}
