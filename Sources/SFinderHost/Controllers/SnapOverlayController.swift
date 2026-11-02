import Cocoa
import SwiftUI
import SFinderCore

@MainActor
public final class SnapOverlayController: NSObject {
    public static let shared = SnapOverlayController()
    
    private var overlayPanel: NSPanel?
    private var currentPosition: SnapPosition?
    private var isAnimating: Bool = false
    
    override private init() {
        super.init()
    }
    
    public func showPreview(frame: CGRect, position: SnapPosition, on screen: NSScreen) {
        if overlayPanel == nil {
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.overlayPanel = panel
        }
        
        guard let panel = overlayPanel else { return }
        
        // Update content if position changed
        if currentPosition != position {
            currentPosition = position
            let view = SnapPreviewOverlayView(position: position)
            panel.contentView = NSHostingView(rootView: view)
        }
        
        if !panel.isVisible {
            panel.setFrame(frame, display: true)
            panel.alphaValue = 0.0
            panel.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
            }
        } else {
            // Smoothly morph between snap zones
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1.0
            }
        }
    }
    
    public func hidePreview() {
        guard let panel = overlayPanel, panel.isVisible else { return }
        currentPosition = nil
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
