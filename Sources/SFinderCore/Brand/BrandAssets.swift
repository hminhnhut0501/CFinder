import AppKit

public final class BrandAssets: Sendable {
    public static let shared = BrandAssets()
    
    public static let colorIconBase64 = "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"
    public static let templateIconBase64 = "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"
    
    private init() {}
    
    public static var appIconImage: NSImage {
        if let data = Data(base64Encoded: colorIconBase64),
           let img = NSImage(data: data) {
            return img
        }
        return NSApp.applicationIconImage
    }
    
    public static var templateIconImage: NSImage {
        if let data = Data(base64Encoded: templateIconBase64),
           let img = NSImage(data: data) {
            img.isTemplate = true
            return img
        }
        return NSImage(systemSymbolName: "pencil.and.list.clipboard", accessibilityDescription: "SFinder") ?? NSImage()
    }
    
    public static func toolbarIcon(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        if let data = Data(base64Encoded: templateIconBase64),
           let img = NSImage(data: data) {
            let resized = NSImage(size: size, flipped: false) { rect in
                img.draw(in: rect)
                return true
            }
            resized.isTemplate = true
            return resized
        }
        return NSImage(systemSymbolName: "pencil.and.list.clipboard", accessibilityDescription: "SFinder") ?? NSImage()
    }
    
    public static func menuBarIcon(isActive: Bool = false) -> NSImage {
        if isActive {
            return wakeActiveIcon()
        } else {
            return wakeInactiveIcon()
        }
    }
    
    /// Biểu tượng trạng thái giữ thức ĐANG BẬT (Active — Awake Eye with Glowing Iris & Infinity)
    public static func wakeActiveIcon(size: NSSize = NSSize(width: 22, height: 18)) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            // Primary warm SFinder orange accent
            let primaryColor = NSColor(red: 1.0, green: 0.35, blue: 0.12, alpha: 1.0)
            let eyeColor = NSColor.white
            
            // Awake Eye outline
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: 1.0, y: 9.0))
            eye.curve(to: NSPoint(x: 11.0, y: 9.0), controlPoint1: NSPoint(x: 6.0, y: 15.0), controlPoint2: NSPoint(x: 6.0, y: 15.0))
            eye.curve(to: NSPoint(x: 1.0, y: 9.0), controlPoint1: NSPoint(x: 6.0, y: 3.0), controlPoint2: NSPoint(x: 6.0, y: 3.0))
            eye.lineWidth = 1.3
            eyeColor.setStroke()
            eye.stroke()
            
            // Glowing Energy Iris / Core
            primaryColor.setFill()
            let pupil = NSBezierPath(ovalIn: NSRect(x: 4.25, y: 7.25, width: 3.5, height: 3.5))
            pupil.fill()
            
            // Infinity emblem on the right (Amphetamine signature)
            let infColor = NSColor(red: 0.25, green: 0.82, blue: 1.0, alpha: 1.0)
            infColor.setStroke()
            let inf = NSBezierPath()
            inf.move(to: NSPoint(x: 14.0, y: 9.0))
            inf.curve(to: NSPoint(x: 17.0, y: 9.0), controlPoint1: NSPoint(x: 14.0, y: 12.0), controlPoint2: NSPoint(x: 17.0, y: 12.0))
            inf.curve(to: NSPoint(x: 20.0, y: 9.0), controlPoint1: NSPoint(x: 17.0, y: 6.0), controlPoint2: NSPoint(x: 20.0, y: 6.0))
            inf.curve(to: NSPoint(x: 17.0, y: 9.0), controlPoint1: NSPoint(x: 20.0, y: 12.0), controlPoint2: NSPoint(x: 17.0, y: 12.0))
            inf.curve(to: NSPoint(x: 14.0, y: 9.0), controlPoint1: NSPoint(x: 17.0, y: 6.0), controlPoint2: NSPoint(x: 14.0, y: 6.0))
            inf.lineWidth = 1.2
            inf.stroke()
            
            return true
        }
        img.isTemplate = false
        return img
    }
    
    /// Biểu tượng trạng thái nghỉ (Inactive — Resting Eye in Template mode)
    public static func wakeInactiveIcon(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            let color = NSColor.textColor
            color.setStroke()
            
            // Resting eye / Sleep contour
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: 2.5, y: 8.5))
            eye.curve(to: NSPoint(x: 15.5, y: 8.5), controlPoint1: NSPoint(x: 9.0, y: 3.5), controlPoint2: NSPoint(x: 9.0, y: 3.5))
            eye.lineWidth = 1.3
            eye.lineCapStyle = .round
            eye.stroke()
            
            // Subtle resting dot
            color.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: 8.0, y: 7.75, width: 2.0, height: 2.0))
            dot.fill()
            
            return true
        }
        img.isTemplate = true
        return img
    }
    
    public static func whiteMenuIcon(size: NSSize = NSSize(width: 16, height: 16)) -> NSImage {
        if let data = Data(base64Encoded: templateIconBase64),
           let img = NSImage(data: data) {
            let whiteImg = NSImage(size: size, flipped: false) { rect in
                NSGraphicsContext.saveGraphicsState()
                img.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                NSGraphicsContext.restoreGraphicsState()
                return true
            }
            whiteImg.isTemplate = false
            return whiteImg
        }
        return NSImage()
    }
}
