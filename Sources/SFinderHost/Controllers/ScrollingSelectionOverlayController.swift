import AppKit
import SwiftUI
import SFinderCore

@MainActor
public final class ScrollingSelectionOverlayController: NSObject {
    public static let shared = ScrollingSelectionOverlayController()
    
    private var overlayPanel: NSPanel?
    private var escKeyMonitor: Any?
    private var onCancelled: (() -> Void)?
    
    override private init() {
        super.init()
    }
    
    public func presentOverlay(onCancelled: (() -> Void)? = nil) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        
        dismissOverlay()
        self.onCancelled = onCancelled
        
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        
        let overlayView = ScrollingSelectionOverlayView(
            screenOrigin: screen.frame.origin,
            onConfirm: { [weak self] selectedScreenRect in
                self?.dismissOverlay()
                ScrollingCaptureEngine.shared.setTargetRect(selectedScreenRect)
                ScrollingCaptureHUDController.shared.showHUD(for: selectedScreenRect)
            },
            onCancel: { [weak self] in
                let cancelHandler = self?.onCancelled
                self?.dismissOverlay()
                cancelHandler?()
                ScrollingCaptureEngine.shared.cancelSession()
            }
        )
        
        panel.contentView = NSHostingView(rootView: overlayView)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        self.overlayPanel = panel
        
        // Listen to Esc key to dismiss
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                let cancelHandler = self?.onCancelled
                self?.dismissOverlay()
                cancelHandler?()
                ScrollingCaptureEngine.shared.cancelSession()
                return nil
            }
            return event
        }
    }
    
    public func dismissOverlay() {
        if let m = escKeyMonitor {
            NSEvent.removeMonitor(m)
            escKeyMonitor = nil
        }
        overlayPanel?.orderOut(nil)
        overlayPanel?.contentView = nil
        overlayPanel = nil
    }
}
