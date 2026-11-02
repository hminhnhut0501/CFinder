import AppKit
import SwiftUI
import SFinderCore

private final class EdgeNotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
public final class EdgeNotesWindowController: NSWindowController, ObservableObject {
    public static let shared = EdgeNotesWindowController()
    
    @Published public private(set) var isVisible: Bool = false
    @Published public var isPinned: Bool = false
    
    private var drawerWidth: CGFloat = 380
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
        panel.hasShadow = false
        panel.sharingType = .readOnly
        
        super.init(window: panel)
        
        let hostingView = NSHostingView(rootView: EdgeNotesDrawerView(controller: self))
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
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let sFrame = screen.visibleFrame
        let drawerHeight = min(680, sFrame.height - 30)
        let drawerY = sFrame.minY + (sFrame.height - drawerHeight) / 2
        
        let offscreenX = screen.frame.maxX
        let targetX = screen.frame.maxX - drawerWidth
        
        if !isVisible {
            // Position offscreen initially
            window.setFrame(NSRect(x: offscreenX, y: drawerY, width: drawerWidth, height: drawerHeight), display: false)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(NSRect(x: targetX, y: drawerY, width: drawerWidth, height: drawerHeight), display: true)
            } completionHandler: { [weak self] in
                self?.isVisible = true
            }
            
            // Listen to Esc key to close if pinned or active
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Esc
                    self?.hideDrawer()
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
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(
                NSRect(x: offscreenX, y: currentFrame.minY, width: drawerWidth, height: currentFrame.height),
                display: true
            )
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
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isVisible, !self.isPinned else { return }
                // Verify mouse is really outside drawer
                let mouse = NSEvent.mouseLocation
                if let win = self.window, !win.frame.insetBy(dx: -10, dy: -10).contains(mouse) {
                    self.hideDrawer()
                }
            }
        }
    }
    
    public func handleMouseEnteredDrawer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
}
