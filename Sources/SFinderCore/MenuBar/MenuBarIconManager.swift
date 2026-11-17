import Foundation
import AppKit
import ApplicationServices

// MARK: - Native macOS MenuBar Visibility Engine (macOS 14+ / macOS 27+)
private final class NativeMenuBarEngine {
    static let shared = NativeMenuBarEngine()
    
    private var isLoaded: Bool = false
    private var configClass: NSObject.Type?
    private var assertionClass: NSObject.Type?
    private var currentAssertion: AnyObject?
    
    // Cache vị trí X của các app khi thanh menu đang ở trạng thái mở rộng (Expanded)
    private var cachedAppMinX: [String: CGFloat] = [:]
    
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
    
    /// Lưu vị trí tọa độ của tất cả các app trên Menu Bar khi thanh menu đang mở hoàn toàn
    func snapshotExpandedPositions() {
        guard isAvailable else { return }
        
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app" }
        
        var newPositions: [String: CGFloat] = [:]
        for app in apps {
            guard let bundle = app.bundleIdentifier else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.08)
            var barValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue) == .success,
                  let bar = barValue else { continue }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement], !children.isEmpty else { continue }
            
            var minAppX: CGFloat = .greatestFiniteMagnitude
            for child in children {
                var posVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posVal) == .success {
                    var pos = CGPoint.zero
                    AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
                    if pos.x > 0 {
                        minAppX = min(minAppX, pos.x)
                    }
                }
            }
            if minAppX < .greatestFiniteMagnitude {
                newPositions[bundle] = minAppX
            }
        }
        
        if !newPositions.isEmpty {
            self.cachedAppMinX = newPositions
        }
    }
    
    /// Ẩn toàn bộ icon nằm bên TRÁI nút mũi tên (arrowX) bằng cơ chế Native Apple Visibility
    func hideIconsLeftOf(arrowX: CGFloat) {
        guard isAvailable, let configClass = configClass, let assertionClass = assertionClass else { return }
        
        // Nếu bộ nhớ tạm chưa có dữ liệu, quét nhanh ngay lúc này
        if cachedAppMinX.isEmpty {
            snapshotExpandedPositions()
        }
        
        var allowedBundles = Set<String>()
        // Luôn luôn cho phép hệ thống macOS và CFinder
        allowedBundles.insert("com.sfinder.app")
        allowedBundles.insert("com.sfinder.host")
        allowedBundles.insert("com.apple.finder")
        if let ownBundle = Bundle.main.bundleIdentifier {
            allowedBundles.insert(ownBundle)
        }
        
        // Các app có tọa độ X nằm bên PHẢI (hoặc bằng) nút mũi tên sẽ tiếp tục được hiển thị
        for (bundle, posX) in cachedAppMinX {
            if posX >= arrowX {
                allowedBundles.insert(bundle)
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
    
    /// Hủy bỏ ẩn biểu tượng, khôi phục thanh Menu Bar trở lại đầy đủ ngay lập tức
    func invalidate() {
        if let a = currentAssertion {
            _ = a.perform(Selector(("invalidate")))
            currentAssertion = nil
        }
    }
}

/// View bắt sự kiện Hover và Click trên nút điều khiển Menu Bar (0% CPU, mượt mà chuẩn macOS)
final class MenuBarHoverTrackingView: NSView {
    weak var manager: MenuBarIconManager?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        manager?.handleHoverEntered()
    }

    override func mouseExited(with event: NSEvent) {
        manager?.handleHoverExited()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Trả về nil để sự kiện click chuột đi thẳng vào NSStatusBarButton bên dưới
        return nil
    }
}

/// Quản lý ẩn/hiện và sắp xếp biểu tượng trên thanh Menu Bar (MenuBar Icons Manager)
/// Tối ưu 100% cho macOS 27: Triệt tiêu hoàn toàn khoảng trống rỗng, không xung đột overflow, không giật lag
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
                onShowToast?("hand.draw.fill", "Chế độ sắp xếp Menu Bar", "Giữ phím ⌘ (Command) và kéo icon qua lại nút mũi tên ◀")
            } else {
                // Thoát chế độ sắp xếp: Lưu vị trí mới của các app và tiếp tục hẹn giờ tự ẩn
                NativeMenuBarEngine.shared.snapshotExpandedPositions()
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
    
    // Hover tracking
    private var hoverTrackingView: MenuBarHoverTrackingView?
    private var hoverDwellTimer: Timer?
    
    private override init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.object(forKey: "sfinder_menubar_hide_enabled") as? Bool ?? true
        self.isCollapsed = defaults.object(forKey: "sfinder_menubar_is_collapsed") as? Bool ?? true
        self.autoHideEnabled = defaults.object(forKey: "sfinder_menubar_autohide_enabled") as? Bool ?? true
        self.autoHideDelay = defaults.object(forKey: "sfinder_menubar_autohide_delay") as? Double ?? 5.0
        self.expandOnHover = defaults.object(forKey: "sfinder_menubar_expand_on_hover") as? Bool ?? true
        self.showSeparator = defaults.object(forKey: "sfinder_menubar_show_separator") as? Bool ?? false
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
        hoverDwellTimer?.invalidate()
        autoHideTimer?.invalidate()
        NativeMenuBarEngine.shared.invalidate()
    }
    
    // MARK: - Lifecycle & Setup
    
    public func setup() {
        guard isEnabled else { return }
        
        // Dọn dẹp bất kỳ separateItem nào từ các phiên bản cũ còn sót lại trong status bar
        if let si = separateItem {
            NSStatusBar.system.removeStatusItem(si)
            separateItem = nil
        }
        
        updateStatusItems()
        setupHoverMonitor()
        
        // Quét lấy vị trí mở rộng ban đầu sau khi thanh menu ổn định
        if !isCollapsed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NativeMenuBarEngine.shared.snapshotExpandedPositions()
            }
        }
    }
    
    @objc private func handleScreenParametersChanged() {
        if isCollapsed {
            applyCollapseState()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NativeMenuBarEngine.shared.snapshotExpandedPositions()
            }
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
        if collapseItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "CFinder_MenuBar_Toggle"
            if let btn = item.button {
                btn.target = self
                btn.action = #selector(handleCollapseClick)
                btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
                
                let trackingView = MenuBarHoverTrackingView(frame: btn.bounds)
                trackingView.autoresizingMask = [.width, .height]
                trackingView.manager = self
                btn.addSubview(trackingView)
                self.hoverTrackingView = trackingView
            }
            self.collapseItem = item
        }
        
        // Trên macOS 27: NativeMenuBarEngine sử dụng nút mũi tên làm ranh giới duy nhất.
        // Loại bỏ hoàn toàn separateItem để không chiếm khoảng trống hoặc gây lỗi overflow >>.
        if NativeMenuBarEngine.shared.isAvailable {
            if let si = separateItem {
                NSStatusBar.system.removeStatusItem(si)
                separateItem = nil
            }
        } else {
            // Fallback chỉ dành cho macOS cũ không có Native Engine
            if showSeparator && separateItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: Self.normalSeparatorLength)
                item.autosaveName = "CFinder_MenuBar_Separator"
                self.separateItem = item
                updateSeparatorVisuals()
            }
        }
    }
    
    private func removeStatusItems() {
        stopAutoHideTimer()
        removeHoverMonitor()
        NativeMenuBarEngine.shared.invalidate()
        
        hoverTrackingView?.removeFromSuperview()
        hoverTrackingView = nil
        
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
    
    @objc func handleCollapseClick() {
        guard isEnabled else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            onOpenSettings?()
            return
        }
        toggle()
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
        guard isEnabled, let col = collapseItem else { return }
        
        let config = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        
        if isCollapsed {
            // Khi thu gọn: Đảm bảo không có separator rác nào làm rách thanh menu
            if let sep = separateItem {
                NSStatusBar.system.removeStatusItem(sep)
                separateItem = nil
            }
            
            // Icon chỉ sang TRÁI (◀): Click để mở rộng hiển thị các icon đang ẩn bên trái
            col.button?.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Hiện biểu tượng")?.withSymbolConfiguration(config)
            col.button?.toolTip = "CFinder: Nhấp để hiển thị các biểu tượng đang ẩn (⌃⌥B)"
            
            if NativeMenuBarEngine.shared.isAvailable {
                guard let window = col.button?.window, window.frame.minX > 100 else {
                    // Nếu status item chưa được WindowServer gắn frame chính xác, thử lại sau 0.15s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        self?.applyCollapseState()
                    }
                    return
                }
                
                // Lấy tọa độ minX của nút Toggle. Tất cả icon có tọa độ X < arrowX sẽ được ẩn sạch sẽ
                let arrowX = window.frame.minX
                NativeMenuBarEngine.shared.hideIconsLeftOf(arrowX: arrowX)
            } else if let sep = separateItem {
                sep.length = 1000.0
            }
        } else {
            if NativeMenuBarEngine.shared.isAvailable {
                NativeMenuBarEngine.shared.invalidate()
                
                // Đợi 0.35s cho macOS WindowServer hiển thị lại các icon đầy đủ, sau đó snapshot tọa độ chính xác
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self = self, !self.isCollapsed else { return }
                    NativeMenuBarEngine.shared.snapshotExpandedPositions()
                }
            } else if let sep = separateItem {
                sep.length = showSeparator ? Self.normalSeparatorLength : 0.0
            }
            
            // Icon chỉ sang PHẢI (▶): Click để thu gọn giấu bớt biểu tượng
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
        guard !NativeMenuBarEngine.shared.isAvailable, let sep = separateItem else { return }
        if showSeparator && !isCollapsed {
            sep.length = Self.normalSeparatorLength
            sep.button?.image = makeSeparatorImage()
            sep.button?.toolTip = "CFinder: Giữ phím ⌘ và kéo biểu tượng sang bên trái vạch này để ẩn"
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
                // Chuột vẫn đang ở trên thanh Menu Bar, gia hạn thêm 2.5s
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
    
    // MARK: - Hover Detection (NSTrackingArea)
    
    private func setupHoverMonitor() {
        // NSTrackingArea được quản lý trực tiếp bên trong MenuBarHoverTrackingView
    }
    
    private func removeHoverMonitor() {
        hoverDwellTimer?.invalidate()
        hoverDwellTimer = nil
    }
    
    func handleHoverEntered() {
        guard expandOnHover && isEnabled else { return }
        if isCollapsed {
            hoverDwellTimer?.invalidate()
            hoverDwellTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.isCollapsed else { return }
                    self.hoverDwellTimer = nil
                    self.expand()
                }
            }
        } else {
            stopAutoHideTimer()
        }
    }
    
    func handleHoverExited() {
        hoverDwellTimer?.invalidate()
        hoverDwellTimer = nil
        if !isCollapsed && autoHideEnabled && !isOrganizingMode {
            startAutoHideTimerIfNeeded()
        }
    }
}
