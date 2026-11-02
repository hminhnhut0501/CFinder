import AppKit
import SwiftUI
import SFinderCore

private final class EdgeNotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var isOpaque: Bool {
        get { false }
        set {}
    }
}

@MainActor
public final class EdgeNotesWindowController: NSWindowController, ObservableObject {
    public static let shared = EdgeNotesWindowController()
    
    @Published public private(set) var isVisible: Bool = false
    @Published public var isPinned: Bool = false
    
    private let drawerWidth: CGFloat = 380
    private var dismissTimer: Timer?
    private var localKeyMonitor: Any?
    
    private init() {
        let panel = EdgeNotesPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 620),
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
        panel.sharingType = .readOnly
        
        super.init(window: panel)
        
        let hostingView = NSHostingView(rootView: EdgeNotesDrawerView(controller: self))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Slide Animations
    
    public func toggleDrawer() {
        if isVisible {
            hideDrawer()
        } else {
            showDrawer()
        }
    }
    
    public func showDrawer() {
        guard let window = window else { return }
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        guard !isVisible else { return }
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sFrame = screen.visibleFrame
        let drawerHeight = min(680, sFrame.height - 30)
        let drawerY = sFrame.minY + (sFrame.height - drawerHeight) / 2
        
        let offscreenX = screen.frame.maxX
        let targetX = screen.frame.maxX - drawerWidth
        
        window.setFrame(NSRect(x: offscreenX, y: drawerY, width: drawerWidth, height: drawerHeight), display: false)
        window.alphaValue = 0.0
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.invalidateShadow()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            window.animator().setFrame(NSRect(x: targetX, y: drawerY, width: drawerWidth, height: drawerHeight), display: true)
            window.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            self?.isVisible = true
            self?.window?.invalidateShadow()
        }
        
        // Listen to Esc key to close if active
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Esc
                    self?.hideDrawer(force: true)
                    return nil
                }
                return event
            }
        }
        
        self.isVisible = true
    }
    
    public func hideDrawer(force: Bool = false) {
        guard let window = window, isVisible else { return }
        if isPinned && !force { return }
        
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
        
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let currentFrame = window.frame
        let offscreenX = screen.frame.maxX
        
        EdgeHotspotController.shared.markJustDismissed()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0.0, 0.2, 1.0)
            window.animator().setFrame(
                NSRect(x: offscreenX, y: currentFrame.minY, width: drawerWidth, height: currentFrame.height),
                display: true
            )
            window.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.isVisible = false
        }
        
        // Auto-save storage when closing
        QuickNotesStorage.shared.saveImmediately()
    }
    
    // MARK: - Mouse Exit Handling
    
    public func handleMouseExitedDrawer() {
        guard isVisible, !isPinned else { return }
        // Start countdown only once (do not restart on every move outside)
        guard dismissTimer == nil else { return }
        
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isVisible, !self.isPinned else { return }
                // Verify mouse is really outside drawer
                let mouse = NSEvent.mouseLocation
                if let win = self.window, !win.frame.insetBy(dx: -10, dy: -10).contains(mouse) {
                    self.hideDrawer()
                } else {
                    self.dismissTimer = nil
                }
            }
        }
    }
    
    public func handleMouseEnteredDrawer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
}
