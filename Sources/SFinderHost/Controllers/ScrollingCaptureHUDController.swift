import AppKit
import SwiftUI
import SFinderCore

public final class ScrollingCaptureHUDController: NSWindowController {
    public static let shared = ScrollingCaptureHUDController()
    
    // Panel hiển thị viền nổi bật bao quanh vùng capture
    private var highlightPanel: NSPanel?
    
    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        super.init(window: panel)
        
        setupEngineCallbacks()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupEngineCallbacks() {
        ScrollingCaptureEngine.shared.onFinished = { [weak self] finalImage in
            self?.hideHUD()
            ScrollingResultViewerController.shared.showResult(image: finalImage)
        }
        
        ScrollingCaptureEngine.shared.onCancel = { [weak self] in
            self?.hideHUD()
            HostActionCoordinator.shared.restoreHiddenWindowsAfterCapture()
        }
    }
    
    public func showHUD(for captureRect: CGRect) {
        guard let window = window else { return }
        
        let hosting = NSHostingView(rootView: ScrollingCaptureHUDView())
        window.contentView = hosting
        
        // Tính toán toạ độ đặt HUD bên cạnh vùng chụp
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(captureRect) }) ?? NSScreen.main ?? NSScreen.screens.first!
        let sFrame = screen.visibleFrame
        
        let hudW: CGFloat = 280
        let hudH: CGFloat = 260
        
        var hudX = captureRect.maxX + 16
        // Nếu bên phải chật, đặt sang bên trái
        if hudX + hudW > sFrame.maxX {
            hudX = captureRect.minX - hudW - 16
        }
        // Nếu vẫn không đủ chỗ, căn giữa mép trên hoặc dưới
        if hudX < sFrame.minX {
            hudX = max(sFrame.minX + 16, min(sFrame.maxX - hudW - 16, captureRect.midX - hudW / 2))
        }
        
        var hudY = captureRect.midY - hudH / 2
        hudY = max(sFrame.minY + 16, min(sFrame.maxY - hudH - 16, hudY))
        
        window.setFrame(NSRect(x: hudX, y: hudY, width: hudW, height: hudH), display: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        // Hiển thị khung viền định vị vùng chụp
        showHighlightBorder(around: captureRect)
    }
    
    public func hideHUD() {
        window?.orderOut(nil)
        highlightPanel?.orderOut(nil)
        highlightPanel = nil
    }
    
    private func showHighlightBorder(around rect: CGRect) {
        highlightPanel?.orderOut(nil)
        
        let p = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        
        let borderView = NSView(frame: NSRect(origin: .zero, size: rect.size))
        borderView.wantsLayer = true
        borderView.layer?.borderWidth = 2.0
        borderView.layer?.borderColor = NSColor.cyan.withAlphaComponent(0.85).cgColor
        borderView.layer?.cornerRadius = 6
        p.contentView = borderView
        
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        self.highlightPanel = p
    }
}
