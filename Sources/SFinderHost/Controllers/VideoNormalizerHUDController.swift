import Cocoa
import SwiftUI
import SFinderCore

@MainActor
public final class VideoNormalizerHUDController: NSObject {
    public static let shared = VideoNormalizerHUDController()
    
    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?
    
    override private init() {
        super.init()
    }
    
    public func show() {
        dismissTask?.cancel()
        dismissTask = nil
        
        let hudView = VideoNormalizerHUDView(
            coordinator: VideoNormalizerBatchCoordinator.shared,
            onCancel: { [weak self] in
                VideoNormalizerBatchCoordinator.shared.cancel()
                self?.hide(animated: true)
            },
            onDismiss: { [weak self] in
                self?.hide(animated: true)
            },
            onRevealInFinder: { [weak self] in
                if let file = VideoNormalizerBatchCoordinator.shared.lastOutputFileURL {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                } else if let dir = VideoNormalizerBatchCoordinator.shared.lastOutputDir {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                }
                self?.hide(animated: true)
            }
        )
        
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.wantsLayer = true
        
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 95),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            self.window = panel
        }
        
        guard let panel = window else { return }
        panel.contentView = hostingView
        panel.layoutIfNeeded()
        
        // Position at top center, 48px below menu bar
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let hudWidth: CGFloat = 420
        let hudHeight: CGFloat = 95
        
        let x = screenFrame.midX - (hudWidth / 2)
        let targetY = screenFrame.maxY - hudHeight - 16
        let startY = screenFrame.maxY + 20
        
        if !panel.isVisible {
            panel.setFrame(NSRect(x: x, y: startY, width: hudWidth, height: hudHeight), display: true)
            panel.alphaValue = 0.0
            panel.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(NSRect(x: x, y: targetY, width: hudWidth, height: hudHeight), display: true)
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.animator().setFrame(NSRect(x: x, y: targetY, width: hudWidth, height: hudHeight), display: true)
        }
    }
    
    public func scheduleAutoDismiss(after delay: TimeInterval = 6.0) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }
    
    public func hide(animated: Bool = true) {
        dismissTask?.cancel()
        dismissTask = nil
        
        guard let panel = window, panel.isVisible else { return }
        
        if animated {
            let currentFrame = panel.frame
            let targetFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y + 24,
                width: currentFrame.width,
                height: currentFrame.height
            )
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(targetFrame, display: true)
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                panel.orderOut(nil)
                panel.setFrame(currentFrame, display: false)
            })
        } else {
            panel.orderOut(nil)
        }
    }
}
