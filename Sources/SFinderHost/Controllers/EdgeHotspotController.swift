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
    private var localMouseMonitor: Any?
    private var hoverTriggerTimer: Timer?
    private var isHoverPending: Bool = false
    private var hoverStartY: CGFloat = 0
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
    }
    
    public func markJustDismissed() {
        lastDismissTimestamp = ProcessInfo.processInfo.systemUptime
        cancelHover()
    }
    
    public func startMonitoring() {
        guard isEdgeTriggerEnabled else { return }
        
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleMouseMove()
                }
            }
        }
        
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleMouseMove()
                }
                return event
            }
        }
        NSLog("[EdgeHotspotController] Started monitoring mouse for edge notes (dwell: \(dwellDuration)s)")
    }
    
    public func stopMonitoring() {
        if let m = globalMouseMonitor {
            NSEvent.removeMonitor(m)
            globalMouseMonitor = nil
        }
        if let m = localMouseMonitor {
            NSEvent.removeMonitor(m)
            localMouseMonitor = nil
        }
        cancelHover()
    }
    
    private func cancelHover() {
        hoverTriggerTimer?.invalidate()
        hoverTriggerTimer = nil
        isHoverPending = false
    }
    
    private func handleMouseMove() {
        guard isEdgeTriggerEnabled else { return }
        let mouse = NSEvent.mouseLocation
        
        // Find screen containing mouse
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return
        }
        
        let drawerController = EdgeNotesWindowController.shared
        
        // 1. If drawer is currently visible: track mouse inside/outside
        if drawerController.isVisible {
            if let win = drawerController.window {
                let expandedFrame = win.frame.insetBy(dx: -10, dy: -10)
                if expandedFrame.contains(mouse) {
                    drawerController.handleMouseEnteredDrawer()
                } else {
                    drawerController.handleMouseExitedDrawer()
                }
            }
            return
        }
        
        // 2. Cooldown check: ignore if user just closed the drawer
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastDismissTimestamp < dismissCooldown {
            cancelHover()
            return
        }
        
        // 3. Touch right edge check (strictly within 1.5 pt of the rightmost display edge)
        let rightEdgeX = screen.frame.maxX - 1.5
        let topDeadZone = screen.visibleFrame.maxY - 50 // Avoid top menu bar & control center
        let bottomDeadZone = screen.visibleFrame.minY + 50 // Avoid bottom corner hot corners
        
        let isTouchingRightEdge = (mouse.x >= rightEdgeX) && (mouse.y >= bottomDeadZone) && (mouse.y <= topDeadZone)
        
        if isTouchingRightEdge {
            if !isHoverPending {
                isHoverPending = true
                hoverStartY = mouse.y
                hoverTriggerTimer?.invalidate()
                
                hoverTriggerTimer = Timer.scheduledTimer(withTimeInterval: dwellDuration, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.isHoverPending = false
                        let currentMouse = NSEvent.mouseLocation
                        
                        // Verify cursor is still at the edge and hasn't drifted wildly vertically
                        if currentMouse.x >= rightEdgeX && abs(currentMouse.y - self.hoverStartY) <= 45 {
                            drawerController.showDrawer()
                        }
                    }
                }
            } else {
                // If the user drags or scrolls quickly vertically, cancel to avoid accidental popups
                if abs(mouse.y - hoverStartY) > 55 {
                    cancelHover()
                }
            }
        } else {
            if isHoverPending {
                cancelHover()
            }
        }
    }
}
