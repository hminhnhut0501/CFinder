import Foundation
import AppKit
import Carbon
import AudioToolbox
import ApplicationServices

@MainActor
public final class WindowSnapManager: ObservableObject {
    public static let shared = WindowSnapManager()
    
    // MARK: - Published State
    @Published public var isSnapEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSnapEnabled, forKey: "sfinder_snap_enabled")
            if isSnapEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    
    @Published public var screenConfigs: [String: ScreenSnapConfig] = [:]
    @Published public var selectedScreenKey: String = ""
    
    // UI Callbacks
    public var onShowPreview: ((_ frame: CGRect, _ position: SnapPosition, _ screen: NSScreen) -> Void)?
    public var onHidePreview: (() -> Void)?
    public var onShowToast: ((_ icon: String, _ title: String, _ subtitle: String) -> Void)?
    
    // Active Drag Tracking State
    private var pendingSnap: (window: AXUIElement, position: SnapPosition, screen: NSScreen)?
    private var isDraggingNearSnapArea: Bool = false
    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var keyMonitor: Any?
    
    private init() {
        self.isSnapEnabled = UserDefaults.standard.object(forKey: "sfinder_snap_enabled") as? Bool ?? true
        loadScreenConfigs()
        if isSnapEnabled {
            startMonitoring()
        }
    }
    
    // MARK: - Screen Config Management
    
    public func config(for screen: NSScreen) -> ScreenSnapConfig {
        let key = screenIdentifier(for: screen)
        if let existing = screenConfigs[key] {
            return existing
        }
        let index = NSScreen.screens.firstIndex(of: screen) ?? 0
        let newCfg = ScreenSnapConfig.default(for: screen, index: index)
        screenConfigs[key] = newCfg
        saveScreenConfigs()
        return newCfg
    }
    
    public func updateConfig(_ config: ScreenSnapConfig) {
        screenConfigs[config.screenKey] = config
        saveScreenConfigs()
    }
    
    public func screenIdentifier(for screen: NSScreen) -> String {
        let index = NSScreen.screens.firstIndex(of: screen) ?? 0
        return "screen_\(Int(screen.frame.width))x\(Int(screen.frame.height))_\(index)"
    }
    
    private func saveScreenConfigs() {
        if let data = try? JSONEncoder().encode(screenConfigs) {
            UserDefaults.standard.set(data, forKey: "sfinder_screen_snap_configs")
        }
    }
    
    private func loadScreenConfigs() {
        if let data = UserDefaults.standard.data(forKey: "sfinder_screen_snap_configs"),
           let decoded = try? JSONDecoder().decode([String: ScreenSnapConfig].self, from: data) {
            self.screenConfigs = decoded
        }
        
        // Ensure all currently attached screens have a config
        for (i, screen) in NSScreen.screens.enumerated() {
            let key = screenIdentifier(for: screen)
            if screenConfigs[key] == nil {
                screenConfigs[key] = ScreenSnapConfig.default(for: screen, index: i)
            }
        }
        if selectedScreenKey.isEmpty, let firstScreen = NSScreen.screens.first {
            selectedScreenKey = screenIdentifier(for: firstScreen)
        }
    }
    
    // MARK: - Monitoring Infrastructure
    
    public func startMonitoring() {
        stopMonitoring()
        guard isSnapEnabled else { return }
        
        // 1. Mouse Dragged Global Monitor
        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleMouseDrag()
        }
        
        // 2. Mouse Up Global Monitor
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp()
        }
        
        // 3. Global Key Monitor for Snap Hotkeys (Control + Option + Key)
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyShortcuts(event)
        }
        
        NSLog("[WindowSnapManager] Started Global Snap Monitoring (Drag to Snap & ⌃⌥ Shortcuts)")
    }
    
    public func stopMonitoring() {
        if let m = mouseDragMonitor {
            NSEvent.removeMonitor(m)
            mouseDragMonitor = nil
        }
        if let m = mouseUpMonitor {
            NSEvent.removeMonitor(m)
            mouseUpMonitor = nil
        }
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        onHidePreview?()
        pendingSnap = nil
        isDraggingNearSnapArea = false
    }
    
    // MARK: - Mouse Event Handlers
    
    private func handleMouseDrag() {
        guard isSnapEnabled else { return }
        
        let mouseLoc = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(mouseLoc, $0.frame) }) else {
            if isDraggingNearSnapArea {
                onHidePreview?()
                pendingSnap = nil
                isDraggingNearSnapArea = false
            }
            return
        }
        
        let cfg = config(for: screen)
        guard let detectedPosition = detectSnapPosition(at: mouseLoc, on: screen, config: cfg) else {
            if isDraggingNearSnapArea {
                onHidePreview?()
                pendingSnap = nil
                isDraggingNearSnapArea = false
            }
            return
        }
        
        // Cursor is in a snap area!
        guard let window = getFrontmostMovableWindow() else {
            return
        }
        
        let previewFrame = detectedPosition.frame(on: screen, gap: cfg.windowGap)
        onShowPreview?(previewFrame, detectedPosition, screen)
        pendingSnap = (window: window, position: detectedPosition, screen: screen)
        isDraggingNearSnapArea = true
    }
    
    private func handleMouseUp() {
        guard isSnapEnabled else { return }
        
        if let pending = pendingSnap {
            onHidePreview?()
            let cfg = config(for: pending.screen)
            applySnap(to: pending.window, position: pending.position, on: pending.screen, gap: cfg.windowGap)
            pendingSnap = nil
            isDraggingNearSnapArea = false
        } else if isDraggingNearSnapArea {
            onHidePreview?()
            isDraggingNearSnapArea = false
        }
    }
    
    // MARK: - Position Detection Algorithm
    
    private func detectSnapPosition(at mouseLoc: NSPoint, on screen: NSScreen, config: ScreenSnapConfig) -> SnapPosition? {
        let f = screen.frame
        let corner = config.cornerSensitivity
        let edge = config.edgeSensitivity
        
        // 1. Four Corners (Chia tư 25%)
        if config.enableCorners {
            if mouseLoc.x <= f.minX + corner && mouseLoc.y >= f.maxY - corner {
                return .topLeft
            } else if mouseLoc.x >= f.maxX - corner && mouseLoc.y >= f.maxY - corner {
                return .topRight
            } else if mouseLoc.x <= f.minX + corner && mouseLoc.y <= f.minY + corner {
                return .bottomLeft
            } else if mouseLoc.x >= f.maxX - corner && mouseLoc.y <= f.minY + corner {
                return .bottomRight
            }
        }
        
        // 2. Edges (Toàn màn hình & Chia đôi 50%)
        if config.enableTopMaximize && mouseLoc.y >= f.maxY - edge {
            return .maximize
        } else if config.enableSideHalves && mouseLoc.x <= f.minX + edge {
            return .leftHalf
        } else if config.enableSideHalves && mouseLoc.x >= f.maxX - edge {
            return .rightHalf
        } else if config.enableBottomHalf && mouseLoc.y <= f.minY + edge {
            return .bottomHalf
        }
        
        return nil
    }
    
    // MARK: - Window Snapping Execution
    
    public func snapFrontmost(to position: SnapPosition) {
        guard let window = getFrontmostMovableWindow() else {
            onShowToast?("exclamationmark.triangle", "Không tìm thấy cửa sổ", "Hãy nhấp chọn cửa sổ bạn muốn chia")
            return
        }
        
        let screen = getScreen(for: window) ?? NSScreen.main ?? NSScreen.screens.first!
        let cfg = config(for: screen)
        applySnap(to: window, position: position, on: screen, gap: cfg.windowGap)
    }
    
    public func applySnap(to window: AXUIElement, position: SnapPosition, on screen: NSScreen, gap: CGFloat) {
        let targetCocoa = position.frame(on: screen, gap: gap)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        let (axOrigin, axSize) = SnapPosition.toAXFrame(targetCocoa, primaryScreenHeight: primaryHeight)
        
        var origin = axOrigin
        var size = axSize
        
        guard let posValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return
        }
        
        // 2-pass robust positioning for native macOS window layout:
        // Pass 1: Set position then size
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        
        // Pass 2: Re-enforce origin in case size changed window constraints
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        
        // Play subtle haptic feedback
        AudioServicesPlaySystemSound(1104)
        onShowToast?(position.icon, position.title, "Khoảng cách viền: \(Int(gap))px")
    }
    
    // MARK: - Accessibility Window Lookups
    
    private func getFrontmostMovableWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue else {
            return nil
        }
        
        let winElem = window as! AXUIElement
        
        // Verify window has position and size attributes
        var posVal: AnyObject?
        var sizeVal: AnyObject?
        guard AXUIElementCopyAttributeValue(winElem, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(winElem, kAXSizeAttribute as CFString, &sizeVal) == .success else {
            return nil
        }
        
        return winElem
    }
    
    private func getScreen(for window: AXUIElement) -> NSScreen? {
        var posVal: AnyObject?
        var sizeVal: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeVal)
        
        var axPos = CGPoint.zero
        var axSize = CGSize.zero
        if let p = posVal { AXValueGetValue(p as! AXValue, .cgPoint, &axPos) }
        if let s = sizeVal { AXValueGetValue(s as! AXValue, .cgSize, &axSize) }
        
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        let cocoaY = primaryHeight - (axPos.y + axSize.height)
        let cocoaCenter = NSPoint(x: axPos.x + axSize.width / 2, y: cocoaY + axSize.height / 2)
        
        return NSScreen.screens.first(where: { NSPointInRect(cocoaCenter, $0.frame) })
    }
    
    // MARK: - Keyboard Shortcut Handler (Control + Option + Key)
    
    private func handleKeyShortcuts(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == [.control, .option] else { return }
        
        let keyCode = event.keyCode
        let char = event.charactersIgnoringModifiers?.lowercased()
        
        switch (keyCode, char) {
        case (126, _): // Up arrow -> Maximize
            snapFrontmost(to: .maximize)
        case (123, _): // Left arrow -> Left Half
            snapFrontmost(to: .leftHalf)
        case (124, _): // Right arrow -> Right Half
            snapFrontmost(to: .rightHalf)
        case (125, _): // Down arrow -> Bottom Half
            snapFrontmost(to: .bottomHalf)
        case (_, "u"): // U -> Top-Left Corner
            snapFrontmost(to: .topLeft)
        case (_, "i"): // I -> Top-Right Corner
            snapFrontmost(to: .topRight)
        case (_, "j"): // J -> Bottom-Left Corner
            snapFrontmost(to: .bottomLeft)
        case (_, "k"): // K -> Bottom-Right Corner
            snapFrontmost(to: .bottomRight)
        case (_, "c"): // C -> Center
            snapFrontmost(to: .center)
        case (36, _):  // Return -> Maximize
            snapFrontmost(to: .maximize)
        default:
            break
        }
    }
}
