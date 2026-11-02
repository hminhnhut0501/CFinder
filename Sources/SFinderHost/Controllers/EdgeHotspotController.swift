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
    
    private var globalMouseMonitor: Any?
    private var hoverTriggerTimer: Timer?
    private var isHoverPending: Bool = false
    
    private init() {
        if UserDefaults.standard.object(forKey: "CFinder_EdgeNotesHoverEnabled") == nil {
            self.isEdgeTriggerEnabled = true
        } else {
            self.isEdgeTriggerEnabled = UserDefaults.standard.bool(forKey: "CFinder_EdgeNotesHoverEnabled")
        }
    }
    
    public func startMonitoring() {
        guard globalMouseMonitor == nil, isEdgeTriggerEnabled else { return }
        
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalMouseMove()
            }
        }
        NSLog("[EdgeHotspotController] Started monitoring mouse for edge notes")
    }
    
    public func stopMonitoring() {
        if let m = globalMouseMonitor {
            NSEvent.removeMonitor(m)
            globalMouseMonitor = nil
        }
        hoverTriggerTimer?.invalidate()
        hoverTriggerTimer = nil
        isHoverPending = false
    }
    
    private func handleGlobalMouseMove() {
        guard isEdgeTriggerEnabled else { return }
        let mouse = NSEvent.mouseLocation
        
        // Find screen containing mouse
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return
        }
        
        let drawerController = EdgeNotesWindowController.shared
        
        // 1. If drawer is currently visible: check if mouse exited
        if drawerController.isVisible {
            if let win = drawerController.window {
                let expandedFrame = win.frame.insetBy(dx: -15, dy: -15)
                if expandedFrame.contains(mouse) {
                    drawerController.handleMouseEnteredDrawer()
                } else {
                    drawerController.handleMouseExitedDrawer()
                }
            }
            return
        }
        
        // 2. If drawer is hidden: check if mouse touches the right edge
        let rightEdgeX = screen.frame.maxX - 4
        let topDeadZone = screen.visibleFrame.maxY - 40 // Avoid top menu bar icons
        let bottomDeadZone = screen.visibleFrame.minY + 40 // Avoid bottom corner hot corners
        
        if mouse.x >= rightEdgeX && mouse.y >= bottomDeadZone && mouse.y <= topDeadZone {
            if !isHoverPending {
                isHoverPending = true
                hoverTriggerTimer?.invalidate()
                // 130ms anti-flicker delay: ensure user deliberately stayed at the edge
                hoverTriggerTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.isHoverPending = false
                        let currentMouse = NSEvent.mouseLocation
                        if currentMouse.x >= rightEdgeX {
                            drawerController.showDrawer()
                        }
                    }
                }
            }
        } else {
            if isHoverPending {
                hoverTriggerTimer?.invalidate()
                hoverTriggerTimer = nil
                isHoverPending = false
            }
        }
    }
}
