import Cocoa
import SwiftUI
import Combine
import Carbon
import AudioToolbox
import SFinderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var globalKeyMonitor: Any?
    var localKeyMonitor: Any?
    private var powerCancellable: AnyCancellable?
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandler: EventHandlerRef?
    
    override init() {
        super.init()
        // Register AppleEvent early so cold-start URLs are never missed
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[SFinderHost] SFinder Batch Rename & Smart Wake App Started.")
        
        // Ensure AppleEvent handler is registered
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        // Initialize coordinator & IPC listener
        _ = HostActionCoordinator.shared
        _ = FloatingHUDController.shared
        
        // Setup status bar item with Smart Power Management
        setupStatusItem()
        
        // Setup global hotkeys (⌥C for OCR, ⌘⇧R for rename, ⌘I for wake toggle)
        setupHotkeys()
        
        // Listen to HotKey changes
        NotificationCenter.default.addObserver(
            forName: ScreenOCREngine.hotKeyChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.registerCarbonHotKey()
            }
        }
        
        // Listen to Distributed IPC for Tab Switching
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sfinder.presentTab"),
            object: nil,
            queue: .main
        ) { notif in
            let tabStr = notif.userInfo?["tab"] as? String ?? "wake"
            let tab = DashboardTab(rawValue: tabStr) ?? .wake
            HostActionCoordinator.shared.presentDashboard(tab: tab)
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sfinder.toggleNetworkSession"),
            object: nil,
            queue: .main
        ) { _ in
            if case .networkIdle = PowerManager.shared.currentSession {
                PowerManager.shared.endSession(reason: "IPC dừng")
            } else {
                PowerManager.shared.startNetworkIdleSession()
            }
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sfinder.startScrollingCapture"),
            object: nil,
            queue: .main
        ) { _ in
            HostActionCoordinator.shared.presentScrollingCapture()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sfinder.toggleMenuBarIcons"),
            object: nil,
            queue: .main
        ) { _ in
            MenuBarIconManager.shared.toggle()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sfinder.startSpeedTest"),
            object: nil,
            queue: .main
        ) { _ in
            SpeedTestEngine.shared.startTest()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sfinder.toggleScreenRecording"),
            object: nil,
            queue: .main
        ) { _ in
            ScreenRecorderEngine.shared.toggleRecording()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.sfinder.toggleEdgeNotes"),
            object: nil,
            queue: .main
        ) { _ in
            EdgeNotesWindowController.shared.toggleDrawer()
        }
        
        // Start Edge Quick Notes screen edge monitor
        EdgeHotspotController.shared.startMonitoring()
    }
    
    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        NSLog("[SFinderHost] Received AppleEvent URL: %@", urlString)
        handleIncomingURL(url)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NSLog("[SFinderHost] application open url: %@", url.absoluteString)
            handleIncomingURL(url)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            HostActionCoordinator.shared.presentDashboard()
        }
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        FinderCutManager.shared.stopGlobalEventTap()
        WindowSnapManager.shared.stopMonitoring()
    }
    
    private func handleIncomingURL(_ url: URL) {
        NSLog("[SFinderHost] handleIncomingURL: %@", url.absoluteString)
        guard url.scheme == "sfinder" else { return }
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value {
                let cleanBase64 = dataParam.replacingOccurrences(of: " ", with: "+")
                if let data = Data(base64Encoded: cleanBase64, options: .ignoreUnknownCharacters),
                   let msg = try? JSONDecoder().decode(IPCMessage.self, from: data) {
                    NSLog("[SFinderHost] Decoded IPCMessage: action=%@, targets=%ld", msg.actionType.rawValue, msg.targetPaths.count)
                    HostActionCoordinator.shared.handleMessage(msg)
                    return
                } else {
                    NSLog("[SFinderHost] Failed to decode base64 dataParam")
                }
            }
        }
        
        if url.host == "ocr" || url.path.contains("ocr") || url.host == "capture" {
            Task {
                _ = try? await ScreenOCREngine.shared.captureScreenInteractively()
            }
        } else if url.host == "dashboard" || url.path.contains("dashboard") {
            var targetTab: DashboardTab? = nil
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let tabVal = components.queryItems?.first(where: { $0.name == "tab" })?.value {
                    switch tabVal.lowercased() {
                    case "overview": targetTab = .overview
                    case "permissions": targetTab = .permissions
                    case "general": targetTab = .general
                    case "ocr": targetTab = .ocr
                    case "recorder": targetTab = .recorder
                    case "wake": targetTab = .wake
                    case "rename": targetTab = .rename
                    case "snap": targetTab = .snap
                    case "menubar": targetTab = .menubar
                    case "monitor": targetTab = .monitor
                    case "network": targetTab = .network
                    default: break
                    }
                }
            }
            HostActionCoordinator.shared.presentDashboard(tab: targetTab)
        } else if url.host == "multi-capture" || url.path.contains("multi") {
            Task {
                _ = try? await ScreenOCREngine.shared.captureMultiRegionInteractively()
            }
        } else if url.host == "ocr-clipboard" || url.path.contains("ocr-clipboard") {
            Task {
                _ = try? await ScreenOCREngine.shared.recognizeFromClipboard()
            }
        } else if url.host == "settings" || url.path.contains("settings") {
            HostActionCoordinator.shared.presentSettings()
        } else if url.host == "history" || url.path.contains("history") {
            HostActionCoordinator.shared.presentOCRHistory()
        } else if url.host == "batch-rename" || url.path.contains("batch-rename") {
            HostActionCoordinator.shared.presentBatchRename(urls: [])
        } else if url.host == "notes" || url.path.contains("notes") || url.host == "edge-notes" {
            EdgeNotesWindowController.shared.toggleDrawer()
        } else if url.host == "wake-toggle" || url.path.contains("wake-toggle") {
            PowerManager.shared.toggleQuickSession()
        } else if url.host == "undo" || url.path.contains("undo") {
            HostActionCoordinator.shared.handleMessage(IPCMessage(actionType: .undoBatchRename))
        } else {
            HostActionCoordinator.shared.presentBatchRename(urls: [])
        }
    }
    
    // MARK: - Smart Power Management Status Bar Integration
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        
        updateStatusItemAppearance()
        
        // Listen to PowerManager state changes in real time
        powerCancellable = Publishers.Merge3(
            PowerManager.shared.$isActive.map { _ in () },
            PowerManager.shared.$remainingSeconds.map { _ in () },
            PowerManager.shared.$currentSession.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in
            self?.updateStatusItemAppearance()
        }
    }
    
    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let pm = PowerManager.shared
        
        button.image = BrandAssets.menuBarIcon(isActive: pm.isActive)
        
        if pm.isActive {
            if let badge = pm.compactBadgeString {
                button.title = " \(badge)"
            } else {
                button.title = ""
            }
            button.toolTip = "CFinder: Đang giữ thức (\(pm.formattedRemainingTime))\nOption-Click hoặc phím ⌘X để dừng"
        } else {
            button.title = ""
            button.toolTip = "CFinder: Chế độ giữ thức đang tắt (Bấm để xem menu, ⌘I để bật nhanh)"
        }
    }
    
    // MARK: - NSMenuDelegate (Dynamic Liquid Glass Menu Generation)
    
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        
        // Minimal Obsidian Liquid Glass Control Center
        let controlCenterView = MenuBarControlCenterView { [weak menu] in
            menu?.cancelTracking()
        }
        let hostingView = NSHostingView(rootView: controlCenterView)
        let fitSize = hostingView.fittingSize
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: max(410, fitSize.height))
        
        let customItem = NSMenuItem()
        customItem.view = hostingView
        menu.addItem(customItem)
    }
    
    // MARK: - Action Handlers
    
    @objc private func handleOpenDashboard() {
        HostActionCoordinator.shared.presentDashboard()
    }
    
    @objc private func handleStartIndefinite() {
        PowerManager.shared.startIndefiniteSession()
    }
    
    @objc private func handleTimedMinutes(_ sender: NSMenuItem) {
        if let mins = sender.representedObject as? Int {
            PowerManager.shared.startTimedSession(minutes: mins)
        }
    }
    
    @objc private func handleTimedHours(_ sender: NSMenuItem) {
        if let hours = sender.representedObject as? Int {
            PowerManager.shared.startTimedSession(hours: hours)
        }
    }
    
    @objc private func handleAppSession(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? NSRunningApplication {
            PowerManager.shared.startAppSession(app: app)
        }
    }
    
    @objc private func handleStartDownloadSleep() {
        PowerManager.shared.startNetworkIdleSession(action: .sleepNow)
    }
    
    @objc private func handleStartDownloadShutDown() {
        PowerManager.shared.startNetworkIdleSession(action: .shutDown)
    }
    
    @objc private func handleStartDownloadAllowIdle() {
        PowerManager.shared.startNetworkIdleSession(action: .allowIdleSleep)
    }
    
    @objc private func handleOpenWakeTab() {
        HostActionCoordinator.shared.presentDashboard(tab: .wake)
    }
    
    @objc private func handleEndSession() {
        PowerManager.shared.endSession()
    }
    
    @objc private func handleToggleDisplaySleep() {
        PowerManager.shared.allowDisplaySleep.toggle()
    }
    
    @objc private func handleToggleLowBattery() {
        PowerManager.shared.stopOnLowBattery.toggle()
    }
    
    @objc private func handleOpenRename() {
        HostActionCoordinator.shared.presentBatchRename(urls: [])
    }
    
    @objc private func handleUndoRename() {
        HostActionCoordinator.shared.handleMessage(IPCMessage(actionType: .undoBatchRename))
    }
    
    @objc private func handleScreenOCR() {
        Task {
            _ = try? await ScreenOCREngine.shared.captureScreenInteractively()
        }
    }
    
    @objc private func handleClipboardOCR() {
        Task {
            _ = try? await ScreenOCREngine.shared.recognizeFromClipboard()
        }
    }
    
    @objc private func handleMultiRegionOCR() {
        Task {
            _ = try? await ScreenOCREngine.shared.captureMultiRegionInteractively()
        }
    }
    
    @objc private func handleToggleTableDetection() {
        ScreenOCREngine.shared.tableDetection.toggle()
    }
    
    @objc private func handleToggleAutoOpenURL() {
        ScreenOCREngine.shared.autoOpenURL.toggle()
    }
    
    @objc private func handleToggleDetectQR() {
        ScreenOCREngine.shared.detectQR.toggle()
    }
    
    @objc private func handleOpenSettings() {
        HostActionCoordinator.shared.presentSettings()
    }
    
    @objc private func handleOpenHistory() {
        HostActionCoordinator.shared.presentOCRHistory()
    }
    
    @objc private func handleToggleIgnoreLineBreaks() {
        ScreenOCREngine.shared.ignoreLineBreaks.toggle()
    }
    
    @objc private func handleToggleSound() {
        ScreenOCREngine.shared.playSound.toggle()
    }
    
    @objc private func handleChangeHotKey(_ sender: NSMenuItem) {
        if let presetID = sender.representedObject as? String {
            ScreenOCREngine.shared.setPreset(id: presetID)
        }
    }
    
    @objc private func handleClearHistory() {
        ScreenOCREngine.shared.clearHistory()
    }
    
    @objc private func handleCopyHistoryItem(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if ScreenOCREngine.shared.playSound {
                AudioServicesPlaySystemSound(1108)
            }
            let center = NSUserNotificationCenter.default
            let notif = NSUserNotification()
            notif.title = "CFinder OCR"
            notif.informativeText = "✓ Đã sao chép lại đoạn văn vào Clipboard."
            center.deliver(notif)
        }
    }
    
    @objc private func handleQuit() {
        PowerManager.shared.endSession(reason: "Thoát ứng dụng CFinder")
        NSApp.terminate(nil)
    }
    
    // MARK: - Global Hotkeys
    
    private var carbonRecordHotKeyRef: EventHotKeyRef?
    private var carbonNotesHotKeyRef: EventHotKeyRef?
    
    private func registerNotesCarbonHotKey() {
        if let ref = carbonNotesHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonNotesHotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: FourCharCode(0x53464E54), id: 3) // 'SFNT'
        let status = RegisterEventHotKey(45, UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &carbonNotesHotKeyRef)
        NSLog("[SFinderHost] Registered Notes Carbon HotKey ⌥N (status=%d)", status)
    }
    
    private func registerRecordCarbonHotKey() {
        if let ref = carbonRecordHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonRecordHotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: FourCharCode(0x53465243), id: 2) // 'SFRC'
        let status = RegisterEventHotKey(15, UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &carbonRecordHotKeyRef)
        NSLog("[SFinderHost] Registered Record Carbon HotKey ⌥R (status=%d)", status)
    }
    
    private func registerCarbonHotKey() {
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
            carbonHotKeyRef = nil
        }
        
        let preset = ScreenOCREngine.shared.currentPreset
        let hotKeyID = EventHotKeyID(signature: FourCharCode(0x53464F43), id: 1) // 'SFOC'
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &carbonHotKeyRef)
        NSLog("[SFinderHost] Registered OCR Carbon HotKey: %@ (status=%d)", preset.displayShortcut, status)
    }
    
    private func setupHotkeys() {
        // 0. Windows-style Finder Cut & Paste (⌘X / ⌘V) Event Tap
        FinderCutManager.shared.onShowToast = { icon, title, subtitle in
            FloatingHUDController.shared.showToast(icon: icon, title: title, subtitle: subtitle)
        }
        FinderCutManager.shared.startGlobalEventTap()
        
        // 0.4. Screen Recorder (Ghi màn hình)
        ScreenRecorderEngine.shared.onShowToast = { icon, title, subtitle in
            FloatingHUDController.shared.showToast(icon: icon, title: title, subtitle: subtitle)
        }
        
        // 0.5. Window Snap Areas (Drag to Snap & ⌃⌥ Shortcuts)
        WindowSnapManager.shared.onShowPreview = { frame, position, screen in
            SnapOverlayController.shared.showPreview(frame: frame, position: position, on: screen)
        }
        WindowSnapManager.shared.onHidePreview = {
            SnapOverlayController.shared.hidePreview()
        }
        WindowSnapManager.shared.onShowToast = { icon, title, subtitle in
            FloatingHUDController.shared.showToast(icon: icon, title: title, subtitle: subtitle)
        }
        WindowSnapManager.shared.startMonitoring()
        
        // 0.7. Scrolling Screenshot (Chụp cuộn)
        ScrollingCaptureEngine.shared.onShowToast = { icon, title, subtitle in
            FloatingHUDController.shared.showToast(icon: icon, title: title, subtitle: subtitle)
        }
        
        // 0.8. Menu Bar Icons Manager (Ẩn/Hiện icon thanh menu)
        MenuBarIconManager.shared.onShowToast = { icon, title, subtitle in
            FloatingHUDController.shared.showToast(icon: icon, title: title, subtitle: subtitle)
        }
        MenuBarIconManager.shared.onOpenSettings = {
            HostActionCoordinator.shared.presentDashboard(tab: .menubar)
        }
        MenuBarIconManager.shared.setup()
        
        // 1. Carbon Global HotKey: Dynamic according to currentPreset — 100% reliable system-wide
        registerCarbonHotKey()
        registerRecordCarbonHotKey()
        registerNotesCarbonHotKey()
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.signature == FourCharCode(0x53464F43) { // 'SFOC'
                DispatchQueue.main.async {
                    Task {
                        _ = try? await ScreenOCREngine.shared.captureScreenInteractively()
                    }
                }
            } else if hkID.signature == FourCharCode(0x53465243) { // 'SFRC'
                DispatchQueue.main.async {
                    ScreenRecorderEngine.shared.toggleRecording()
                }
            } else if hkID.signature == FourCharCode(0x53464E54) { // 'SFNT'
                DispatchQueue.main.async {
                    EdgeNotesWindowController.shared.toggleDrawer()
                }
            }
            return noErr
        }, 1, &eventType, nil, &carbonEventHandler)
        
        // 2. Global NSEvent monitor
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let key = event.charactersIgnoringModifiers?.lowercased()
            let preset = ScreenOCREngine.shared.currentPreset
            
            // Check current dynamic OCR shortcut or ⌥C fallback
            if (event.keyCode == preset.keyCode && flags.rawValue & 0xFFFF0000 == preset.modifiers) || (flags == [.option] && (event.keyCode == 8 || key == "c")) {
                DispatchQueue.main.async {
                    Task {
                        _ = try? await ScreenOCREngine.shared.captureScreenInteractively()
                    }
                }
            }
            // ⌘D: Open SFinder Dashboard
            else if flags == [.command] && (event.keyCode == 2 || key == "d") {
                DispatchQueue.main.async {
                    HostActionCoordinator.shared.presentDashboard()
                }
            }
            // ⌘⇧R: Open Batch Rename Studio
            else if flags == [.command, .shift] && (event.keyCode == 15 || key == "r") {
                DispatchQueue.main.async {
                    HostActionCoordinator.shared.presentBatchRename(urls: [])
                }
            }
            // ⌘, : Open Settings
            else if flags == [.command] && (event.keyCode == 43 || key == ",") {
                DispatchQueue.main.async {
                    HostActionCoordinator.shared.presentSettings()
                }
            }
            // ⌘I: Toggle Wake Session (Start/Stop)
            else if flags == [.command] && key == "i" {
                DispatchQueue.main.async {
                    PowerManager.shared.toggleQuickSession()
                }
            }
            // ⌥S: Scrolling Screenshot (Chụp cuộn)
            else if flags == [.option] && (event.keyCode == 1 || key == "s") {
                DispatchQueue.main.async {
                    HostActionCoordinator.shared.presentScrollingCapture()
                }
            }
            // ⌥R: Screen Recording (Ghi màn hình)
            else if flags == [.option] && (event.keyCode == 15 || key == "r") {
                DispatchQueue.main.async {
                    ScreenRecorderEngine.shared.toggleRecording()
                }
            }
            // ⌥N: Edge Quick Notes (Ghi chú mép màn hình)
            else if flags == [.option] && (event.keyCode == 45 || key == "n") {
                DispatchQueue.main.async {
                    EdgeNotesWindowController.shared.toggleDrawer()
                }
            }
            // ⌃⌥B / ⌥B: Toggle Menu Bar Icons (Ẩn/Hiện icon thanh menu)
            else if (flags == [.control, .option] || flags == [.option]) && (event.keyCode == 11 || key == "b") {
                DispatchQueue.main.async {
                    MenuBarIconManager.shared.toggle()
                }
            }
        }
        
        // 3. Local NSEvent monitor
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let key = event.charactersIgnoringModifiers?.lowercased()
            let preset = ScreenOCREngine.shared.currentPreset
            
            if (event.keyCode == preset.keyCode && flags.rawValue & 0xFFFF0000 == preset.modifiers) || (flags == [.option] && (event.keyCode == 8 || key == "c")) {
                DispatchQueue.main.async {
                    Task {
                        _ = try? await ScreenOCREngine.shared.captureScreenInteractively()
                    }
                }
                return nil
            } else if flags == [.command] && (event.keyCode == 2 || key == "d") {
                DispatchQueue.main.async {
                    HostActionCoordinator.shared.presentDashboard()
                }
                return nil
            } else if flags == [.command, .shift] && (event.keyCode == 15 || key == "r") {
                DispatchQueue.main.async {
                    HostActionCoordinator.shared.presentBatchRename(urls: [])
                }
                return nil
            } else if flags == [.command] && (event.keyCode == 43 || key == ",") {
                DispatchQueue.main.async {
                    HostActionCoordinator.shared.presentSettings()
                }
                return nil
            } else if flags == [.command] && key == "i" {
                DispatchQueue.main.async {
                    PowerManager.shared.toggleQuickSession()
                }
                return nil
            } else if flags == [.option] && (event.keyCode == 1 || key == "s") {
                DispatchQueue.main.async {
                    HostActionCoordinator.shared.presentScrollingCapture()
                }
                return nil
            } else if flags == [.option] && (event.keyCode == 15 || key == "r") {
                DispatchQueue.main.async {
                    ScreenRecorderEngine.shared.toggleRecording()
                }
                return nil
            } else if flags == [.option] && (event.keyCode == 45 || key == "n") {
                DispatchQueue.main.async {
                    EdgeNotesWindowController.shared.toggleDrawer()
                }
                return nil
            } else if (flags == [.control, .option] || flags == [.option]) && (event.keyCode == 11 || key == "b") {
                DispatchQueue.main.async {
                    MenuBarIconManager.shared.toggle()
                }
                return nil
            } else if flags == [.command] && key == "x" && PowerManager.shared.isActive {
                DispatchQueue.main.async {
                    PowerManager.shared.endSession()
                }
                return nil
            }
            return event
        }
    }
}

let app = NSApplication.shared
@MainActor private var globalAppDelegate: AppDelegate?

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    globalAppDelegate = delegate
    app.delegate = delegate
    app.run()
}
