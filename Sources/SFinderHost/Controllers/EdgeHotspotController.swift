import AppKit
import SFinderCore

@MainActor
public final class EdgeHotspotController: ObservableObject {
    public static let shared = EdgeHotspotController()
    
    @Published public var isEdgeTriggerEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEdgeTriggerEnabled, forKey: "CFinder_EdgeNotesHoverEnabled")
            if isEdgeTriggerEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    private var hotspotWindows: [NSWindow] = []
    private var hoverTriggerTimer: Timer?
    private var lastDismissTimestamp: TimeInterval = 0
    
    // Configurable dwell parameters
    private let dwellDuration: TimeInterval = 0.32 // 320ms deliberate dwell
    private let dismissCooldown: TimeInterval = 0.75 // 750ms cooldown after manual or auto dismiss
    
    private init() {
        if UserDefaults.standard.object(forKey: "CFinder_EdgeNotesHoverEnabled") == nil {
            self.isEdgeTriggerEnabled = true
        } else {
            self.isEdgeTriggerEnabled = UserDefaults.standard.bool(forKey: "CFinder_EdgeNotesHoverEnabled")
        }
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recreateHotspotWindows()
        }
    }
    
    public func markJustDismissed() {
        lastDismissTimestamp = ProcessInfo.processInfo.systemUptime
        cancelHover()
    }
    
    public func startMonitoring() {
        guard isEdgeTriggerEnabled else { return }
        recreateHotspotWindows()
        NSLog("[EdgeHotspotController] Started native edge tracking areas for edge notes")
    }
    
    public func stopMonitoring() {
        cancelHover()
        for win in hotspotWindows {
            win.orderOut(nil)
        }
        hotspotWindows.removeAll()
    }
    
    private func cancelHover() {
        hoverTriggerTimer?.invalidate()
        hoverTriggerTimer = nil
    }
    
    private func recreateHotspotWindows() {
        for win in hotspotWindows {
            win.orderOut(nil)
        }
        hotspotWindows.removeAll()
        guard isEdgeTriggerEnabled else { return }
        
        for screen in NSScreen.screens {
            let sFrame = screen.frame
            let vFrame = screen.visibleFrame
            
            // 2px wide strip along the right edge, avoiding top menu bar and bottom corners
            let topMargin: CGFloat = 50
            let bottomMargin: CGFloat = 50
            let stripHeight = max(100, vFrame.height - topMargin - bottomMargin)
            let stripY = vFrame.minY + bottomMargin
            let stripX = sFrame.maxX - 2
            
            let rect = NSRect(x: stripX, y: stripY, width: 2, height: stripHeight)
            let panel = NSPanel(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            
            let stripView = EdgeHotspotStripView(frame: NSRect(x: 0, y: 0, width: 2, height: stripHeight))
            stripView.onMouseEnter = { [weak self, weak screen] in
                self?.handleEdgeTouch(on: screen)
            }
            stripView.onMouseExit = { [weak self] in
                self?.cancelHover()
            }
            panel.contentView = stripView
            panel.orderFrontRegardless()
            hotspotWindows.append(panel)
        }
    }
    
    private func handleEdgeTouch(on screen: NSScreen?) {
        guard isEdgeTriggerEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDismissTimestamp >= dismissCooldown else { return }
        
        cancelHover()
        hoverTriggerTimer = Timer.scheduledTimer(withTimeInterval: dwellDuration, repeats: false) { [weak self] _ in
            guard let self = self, self.isEdgeTriggerEnabled else { return }
            self.hoverTriggerTimer = nil
            
            guard !EdgeNotesWindowController.shared.isVisible else { return }
            
            let mouse = NSEvent.mouseLocation
            let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first!
            if mouse.x >= targetScreen.frame.maxX - 6.0 {
                EdgeNotesWindowController.shared.showDrawer()
            }
        }
    }
}

final class EdgeHotspotStripView: NSView {
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
    
    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }
    
    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }
}
