import AppKit
import SwiftUI
import SFinderCore

public final class RecordingIndicatorHUDController: NSWindowController {
    public static let shared = RecordingIndicatorHUDController()
    
    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 195, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.sharingType = .none // Hoàn toàn tàng hình trước screencapture / bộ quay video
        panel.isMovableByWindowBackground = true
        super.init(window: panel)
        
        let hosting = NSHostingView(rootView: RecordingIndicatorHUDView())
        panel.contentView = hosting
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show(region: CGRect? = nil) {
        guard let window = window else { return }
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sFrame = screen.visibleFrame
        
        if let rect = region {
            // Đặt thanh chỉ báo ngay trên mép trên của vùng quay (hoặc mép dưới nếu sát đỉnh màn hình)
            var hudX = max(sFrame.minX + 10, min(sFrame.maxX - 205, rect.minX))
            var hudY = rect.maxY + 8
            if hudY + 40 > sFrame.maxY {
                hudY = rect.minY - 46
            }
            if hudY < sFrame.minY {
                hudY = sFrame.maxY - 46
                hudX = sFrame.maxX - 215
            }
            
            window.setFrame(NSRect(x: hudX, y: hudY, width: 195, height: 38), display: true)
        } else {
            // Toàn màn hình: Đặt ở góc trên bên phải màn hình
            let x = sFrame.maxX - 215
            let y = sFrame.maxY - 46
            window.setFrame(NSRect(x: x, y: y, width: 195, height: 38), display: true)
        }
        
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
    
    public func hide() {
        window?.orderOut(nil)
    }
}
