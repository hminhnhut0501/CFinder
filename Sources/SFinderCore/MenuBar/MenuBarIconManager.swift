import Foundation
import AppKit
import ApplicationServices

// MARK: - Native macOS 27 MenuBar Visibility Engine
private final class NativeMenuBarEngine {
    static let shared = NativeMenuBarEngine()
    
    private var isLoaded: Bool = false
    private var configClass: NSObject.Type?
    private var assertionClass: NSObject.Type?
    private var currentAssertion: AnyObject?
    
    init() {
        if let _ = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_NOW | RTLD_LOCAL) {
            self.configClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type
            self.assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type
            self.isLoaded = (configClass != nil && assertionClass != nil)
        }
    }
    
    var isAvailable: Bool {
        return isLoaded
    }
    
    func hideIconsLeftOf(arrowX: CGFloat) {
        guard isAvailable, let configClass = configClass, let assertionClass = assertionClass else { return }
        
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
            .map { (pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier) }
        
        var allowedBundles = Set<String>()
        // System and CFinder bundles always allowed
        allowedBundles.insert("com.sfinder.app")
        allowedBundles.insert("com.sfinder.host")
        allowedBundles.insert("com.apple.finder")
        if let ownBundle = Bundle.main.bundleIdentifier {
            allowedBundles.insert(ownBundle)
        }
        
        for app in apps {
            guard let bundle = app.bundleIdentifier else { continue }
            let element = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(element, 0.05)
            var barValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue) == .success,
                  let bar = barValue else { continue }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else { continue }
            for child in children {
                var posVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posVal) == .success {
                    var pos = CGPoint.zero
                    AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
                    // Icons positioned to the RIGHT of the arrow stay visible
                    if pos.x > arrowX {
                        allowedBundles.insert(bundle)
                    }
                }
            }
        }
        
        invalidate()
        
        let allowedSystem = Array(0..<64).map { NSNumber(value: $0) } as NSArray
        let allowedArray = Array(allowedBundles) as NSArray
        
        let selInit = Selector(("initWithAllowedSystemItems:allowedBundleIdentifiers:"))
        let config = configClass.perform(Selector(("alloc"))).takeUnretainedValue()
        _ = config.perform(selInit, with: allowedSystem, with: allowedArray)
        
        let assertion = assertionClass.perform(Selector(("alloc"))).takeUnretainedValue()
        let selActivate = Selector(("activateWithConfiguration:completionHandler:"))
        
        typealias ActivateBlock = @convention(block) (NSError?) -> Void
        let block: ActivateBlock = { err in
            if let err = err {
                NSLog("[CFinder] NativeMenuBarEngine activation warning: \(err)")
            }
        }
        _ = assertion.perform(selActivate, with: config, with: block)
        self.currentAssertion = assertion
    }
    
    func invalidate() {
        if let a = currentAssertion {
            _ = a.perform(Selector(("invalidate")))
            currentAssertion = nil
        }
    }
}

/// Quản lý ẩn/hiện và sắp xếp biểu tượng trên thanh Menu Bar (MenuBar Icons Manager)
/// Cơ chế Native Visibility cho macOS 27+ kết hợp Spacer-Collapse cho macOS cũ
@MainActor
public final class MenuBarIconManager: NSObject, ObservableObject {
    public static let shared = MenuBarIconManager()
    
    public static let normalSeparatorLength: CGFloat = 16.0
    
    // MARK: - Published Properties
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "sfinder_menubar_hide_enabled")
            updateStatusItems()
        }
    }
    
    @Published public var isCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isCollapsed, forKey: "sfinder_menubar_is_collapsed")
            applyCollapseState()
        }
    }
    
    @Published public var autoHideEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoHideEnabled, forKey: "sfinder_menubar_autohide_enabled")
            if !autoHideEnabled {
                stopAutoHideTimer()
            } else if !isCollapsed && !isOrganizingMode {
                startAutoHideTimerIfNeeded()
            }
        }
    }
    
    @Published public var autoHideDelay: Double {
        didSet {
            UserDefaults.standard.set(autoHideDelay, forKey: "sfinder_menubar_autohide_delay")
            if !isCollapsed && !isOrganizingMode {
                startAutoHideTimerIfNeeded()
            }
        }
    }
    
    @Published public var expandOnHover: Bool {
        didSet {
            UserDefaults.standard.set(expandOnHover, forKey: "sfinder_menubar_expand_on_hover")
            setupHoverMonitor()
        }
    }
    
    @Published public var showSeparator: Bool {
        didSet {
            UserDefaults.standard.set(showSeparator, forKey: "sfinder_menubar_show_separator")
            updateSeparatorVisuals()
        }
    }
    
    /// Chế độ sắp xếp icon: Giữ thanh menu luôn mở và tạm dừng tự động ẩn để người dùng thoải mái kéo thả bằng ⌘
    @Published public var isOrganizingMode: Bool = false {
        didSet {
            if isOrganizingMode {
                stopAutoHideTimer()
                expand()
                onShowToast?("hand.draw.fill", "Chế độ sắp xếp Menu Bar", "Giữ phím ⌘ (Command) và kéo icon qua lại vạch |")
            } else {
                if autoHideEnabled {
                    startAutoHideTimerIfNeeded()
                }
            }
        }
    }
    
    // Callbacks
    public var onShowToast: ((String, String, String) -> Void)?
    public var onOpenSettings: (() -> Void)?
    
    // Status Items
    private var collapseItem: NSStatusItem?
    private var separateItem: NSStatusItem?
    private var autoHideTimer: Timer?
    
    // Global and local hover monitors
    private var globalHoverMonitor: Any?
    private var localHoverMonitor: Any?
    private var hoverDwellTimer: Timer?
    
    private var dynamicCollapsedLength: CGFloat {
        let maxScreenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 1920
        return max(800, min(maxScreenWidth * 2, 10_000))
    }
    
    private override init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.object(forKey: "sfinder_menubar_hide_enabled") as? Bool ?? true
        self.isCollapsed = defaults.object(forKey: "sfinder_menubar_is_collapsed") as? Bool ?? true
        self.autoHideEnabled = defaults.object(forKey: "sfinder_menubar_autohide_enabled") as? Bool ?? true
        self.autoHideDelay = defaults.object(forKey: "sfinder_menubar_autohide_delay") as? Double ?? 5.0
        self.expandOnHover = defaults.object(forKey: "sfinder_menubar_expand_on_hover") as? Bool ?? true
        // Default separator line to false to keep menubar clean
        if defaults.object(forKey: "sfinder_menubar_show_separator_v2") == nil {
            defaults.set(false, forKey: "sfinder_menubar_show_separator")
            defaults.set(true, forKey: "sfinder_menubar_show_separator_v2")
            self.showSeparator = false
        } else {
            self.showSeparator = defaults.object(forKey: "sfinder_menubar_show_separator") as? Bool ?? false
        }
        super.init()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let gm = globalHoverMonitor { NSEvent.removeMonitor(gm) }
        if let lm = localHoverMonitor { NSEvent.removeMonitor(lm) }
        hoverDwellTimer?.invalidate()
        autoHideTimer?.invalidate()
        NativeMenuBarEngine.shared.invalidate()
    }
    
    // MARK: - Lifecycle & Setup
    
    public func setup() {
        guard isEnabled else { return }
        updateStatusItems()
        setupHoverMonitor()
    }
    
    @objc private func handleScreenParametersChanged() {
        if isCollapsed {
            applyCollapseState()
        }
    }
    
    private func updateStatusItems() {
        if isEnabled {
            createStatusItemsIfNeeded()
            applyCollapseState()
            setupHoverMonitor()
        } else {
            removeStatusItems()
            removeHoverMonitor()
        }
    }
    
    private func createStatusItemsIfNeeded() {
        // Thứ tự tạo item trong macOS:
        // Item 1 (collapseItem): Nằm bên PHẢI (giáp khu vực icon luôn hiện)
        // Item 2 (separateItem): Nằm bên TRÁI collapseItem (ngăn cách khu vực icon ẩn)
        if collapseItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "CFinder_MenuBar_Toggle"
            if let btn = item.button {
                btn.target = self
                btn.action = #selector(handleCollapseClick)
                btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            self.collapseItem = item
        }
        
        if separateItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: showSeparator ? Self.normalSeparatorLength : 0.0)
            item.autosaveName = "CFinder_MenuBar_Separator"
            if let btn = item.button {
                btn.target = self
                btn.action = #selector(handleSeparatorClick)
                btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            self.separateItem = item
            updateSeparatorVisuals()
        }
    }
    
    private func removeStatusItems() {
        stopAutoHideTimer()
        removeHoverMonitor()
        NativeMenuBarEngine.shared.invalidate()
        
        if let ci = collapseItem {
            NSStatusBar.system.removeStatusItem(ci)
            collapseItem = nil
        }
        if let si = separateItem {
            NSStatusBar.system.removeStatusItem(si)
            separateItem = nil
        }
    }
    
    // MARK: - Click Handlers
    
    @objc private func handleCollapseClick() {
        guard isEnabled else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            onOpenSettings?()
            return
        }
        toggle()
    }
    
    @objc private func handleSeparatorClick() {
        guard isEnabled else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            onOpenSettings?()
            return
        }
    }
    
    // MARK: - Collapse & Expand Actions
    
    public func toggle() {
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }
    
    public func expand() {
        guard isEnabled else { return }
        isCollapsed = false
        if autoHideEnabled && !isOrganizingMode {
            startAutoHideTimerIfNeeded()
        }
    }
    
    public func collapse() {
        guard isEnabled else { return }
        stopAutoHideTimer()
        isOrganizingMode = false
        isCollapsed = true
    }
    
    private func applyCollapseState() {
        guard isEnabled, let sep = separateItem, let col = collapseItem else { return }
        
        let config = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        
        if isCollapsed {
            col.button?.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Hiện biểu tượng")?.withSymbolConfiguration(config)
            col.button?.toolTip = "CFinder: Nhấp để hiển thị các biểu tượng đang ẩn (⌃⌥B)"
            
            if NativeMenuBarEngine.shared.isAvailable {
                sep.length = 0.0
                sep.button?.image = nil
                let arrowX = col.button?.window?.frame.midX ?? 1150.0
                NativeMenuBarEngine.shared.hideIconsLeftOf(arrowX: arrowX)
            } else {
                sep.length = dynamicCollapsedLength
            }
        } else {
            if NativeMenuBarEngine.shared.isAvailable {
                NativeMenuBarEngine.shared.invalidate()
            }
            
            sep.length = showSeparator ? Self.normalSeparatorLength : 0.0
            col.button?.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Giấu bớt biểu tượng")?.withSymbolConfiguration(config)
            col.button?.toolTip = "CFinder: Nhấp để thu gọn giấu biểu tượng (⌃⌥B)"
        }
        
        updateSeparatorVisuals()
    }
    
    private func makeSeparatorImage() -> NSImage {
        let size = NSSize(width: 8, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath(roundedRect: NSRect(x: 3.25, y: 2, width: 1.5, height: 14), xRadius: 0.75, yRadius: 0.75)
            NSColor.labelColor.withAlphaComponent(0.45).setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
    
    private func updateSeparatorVisuals() {
        guard let sep = separateItem else { return }
        if showSeparator {
            if !isCollapsed {
                sep.length = Self.normalSeparatorLength
                sep.button?.image = makeSeparatorImage()
                sep.button?.toolTip = "CFinder: Giữ phím ⌘ và kéo biểu tượng sang bên trái vạch này để ẩn"
            } else {
                sep.length = 0.0
                sep.button?.image = nil
                sep.button?.toolTip = nil
            }
        } else {
            sep.length = 0.0
            sep.button?.image = nil
            sep.button?.toolTip = nil
        }
    }
    
    // MARK: - Auto-Hide Inactivity Timer
    
    private func startAutoHideTimerIfNeeded() {
        stopAutoHideTimer()
        guard autoHideEnabled && autoHideDelay > 0 && !isOrganizingMode else { return }
        
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleAutoHideTrigger()
            }
        }
    }
    
    private func stopAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }
    
    private func handleAutoHideTrigger() {
        guard !isCollapsed && !isOrganizingMode else { return }
        
        let mouseLoc = NSEvent.mouseLocation
        let primaryScreen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
        
        if let screen = primaryScreen {
            let inMenuBar = (mouseLoc.y >= screen.visibleFrame.maxY && mouseLoc.y <= screen.frame.maxY)
            if inMenuBar {
                autoHideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handleAutoHideTrigger()
                    }
                }
                return
            }
        }
        
        collapse()
    }
    
    // MARK: - Hover Detection (Global Event Monitor)
    
    private func setupHoverMonitor() {
        removeHoverMonitor()
        guard expandOnHover && isEnabled else { return }
        
        globalHoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseMovement(event: event)
            }
        }
        
        localHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseMovement(event: event)
            }
            return event
        }
    }
    
    private func removeHoverMonitor() {
        if let gm = globalHoverMonitor {
            NSEvent.removeMonitor(gm)
            globalHoverMonitor = nil
        }
        if let lm = localHoverMonitor {
            NSEvent.removeMonitor(lm)
            localHoverMonitor = nil
        }
        hoverDwellTimer?.invalidate()
        hoverDwellTimer = nil
    }
    
    private func handleMouseMovement(event: NSEvent) {
        guard expandOnHover, isEnabled else { return }
        let mouseLoc = NSEvent.mouseLocation
        
        guard let button = collapseItem?.button,
              let window = button.window else { return }
        
        let buttonScreenRect = window.frame
        let hitTarget = buttonScreenRect.insetBy(dx: -8, dy: -4)
        
        if hitTarget.contains(mouseLoc) {
            if isCollapsed {
                if hoverDwellTimer == nil {
                    hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self = self, self.isCollapsed else { return }
                            self.hoverDwellTimer = nil
                            let currentPos = NSEvent.mouseLocation
                            if hitTarget.contains(currentPos) {
                                self.expand()
                            }
                        }
                    }
                }
            } else {
                stopAutoHideTimer()
            }
        } else {
            hoverDwellTimer?.invalidate()
            hoverDwellTimer = nil
            
            if !isCollapsed && autoHideEnabled && !isOrganizingMode {
                let primaryScreen = NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main
                if let screen = primaryScreen {
                    let inMenuBar = (mouseLoc.y >= screen.visibleFrame.maxY && mouseLoc.y <= screen.frame.maxY)
                    if inMenuBar {
                        stopAutoHideTimer()
                    } else {
                        if autoHideTimer == nil {
                            startAutoHideTimerIfNeeded()
                        }
                    }
                }
            }
        }
    }
}
