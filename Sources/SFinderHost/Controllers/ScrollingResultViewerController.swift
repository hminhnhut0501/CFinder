import AppKit
import SwiftUI

public final class ScrollingResultViewerController: NSWindowController, NSWindowDelegate {
    public static let shared = ScrollingResultViewerController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "CFinder — Kết quả Chụp cuộn"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        super.init(window: window)
        window.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func windowWillClose(_ notification: Notification) {
        HostActionCoordinator.shared.restoreHiddenWindowsAfterCapture()
    }
    
    public func showResult(image: NSImage) {
        guard let window = window else { return }
        
        let hosting = NSHostingView(
            rootView: ScrollingResultView(image: image, onDismiss: { [weak self] in
                self?.dismiss()
            })
        )
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 16
        hosting.layer?.masksToBounds = true
        
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func dismiss() {
        window?.orderOut(nil)
        window?.contentView = nil
        HostActionCoordinator.shared.restoreHiddenWindowsAfterCapture()
    }
}
