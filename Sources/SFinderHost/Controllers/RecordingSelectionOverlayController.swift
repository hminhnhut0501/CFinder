import AppKit
import SwiftUI
import SFinderCore

private final class RecordingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
public final class RecordingSelectionOverlayController: NSObject {
    public static let shared = RecordingSelectionOverlayController()
    
    private var overlayPanel: NSPanel?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    
    override private init() {
        super.init()
    }
    
    public func presentOverlay(
        onConfirmRegion: @escaping (CGRect) -> Void,
        onConfirmFullScreen: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        
        dismissOverlay()
        
        let panel = RecordingOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
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
        
        let overlayView = RecordingSelectionOverlayView(
            screenOrigin: screen.frame.origin,
            onConfirmRegion: { [weak self] rect in
                self?.dismissOverlay()
                onConfirmRegion(rect)
            },
            onConfirmFullScreen: { [weak self] in
                self?.dismissOverlay()
                onConfirmFullScreen()
            },
            onCancel: { [weak self] in
                self?.dismissOverlay()
                onCancel()
            }
        )
        
        panel.contentView = NSHostingView(rootView: overlayView)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
        self.overlayPanel = panel
        
        // Listen to Esc (53) and Space (49) locally
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc -> Cancel
                self?.dismissOverlay()
                onCancel()
                return nil
            } else if event.keyCode == 49 { // Space -> Full Screen
                self?.dismissOverlay()
                onConfirmFullScreen()
                return nil
            }
            return event
        }
        
        // Listen to Esc (53) globally as fallback
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.dismissOverlay()
                    onCancel()
                }
            } else if event.keyCode == 49 {
                Task { @MainActor in
                    self?.dismissOverlay()
                    onConfirmFullScreen()
                }
            }
        }
    }
    
    public func dismissOverlay() {
        NSCursor.pop()
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        if let gm = globalKeyMonitor {
            NSEvent.removeMonitor(gm)
            globalKeyMonitor = nil
        }
        overlayPanel?.orderOut(nil)
        overlayPanel?.contentView = nil
        overlayPanel = nil
    }
}
