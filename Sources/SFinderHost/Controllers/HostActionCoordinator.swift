import Foundation
import AppKit
import SwiftUI
import SFinderCore

final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    
    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
public final class HostActionCoordinator: ObservableObject {
    public static let shared = HostActionCoordinator()
    
    @Published public var dashboardWindowController: NSWindowController?
    @Published public var renameWindowController: NSWindowController?
    @Published public var videoTwinWindowController: NSWindowController?
    @Published public var videoInspectorWindowController: NSWindowController?
    @Published public var settingsWindowController: NSWindowController?
    @Published public var historyWindowController: NSWindowController?
    @Published public var currentRenameURLs: [URL] = []
    
    private var renameDelegate: WindowCloseDelegate?
    private var videoTwinDelegate: WindowCloseDelegate?
    private var videoInspectorDelegate: WindowCloseDelegate?
    private var dashboardDelegate: WindowCloseDelegate?
    private var settingsDelegate: WindowCloseDelegate?
    private var historyDelegate: WindowCloseDelegate?
    
    private init() {
        setupIPCListener()
        setupCaptureAndRecordingObservers()
    }
    
    private func setupCaptureAndRecordingObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CFinderHideAllWindowsForCapture"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideAllWindowsForCapture()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CFinderRestoreWindowsAfterCapture"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreHiddenWindowsAfterCapture()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CFinderShowRecordingHUD"),
            object: nil,
            queue: .main
        ) { notif in
            let rect = (notif.userInfo?["region"] as? NSValue)?.rectValue
            RecordingIndicatorHUDController.shared.show(region: rect)
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CFinderHideRecordingHUD"),
            object: nil,
            queue: .main
        ) { _ in
            RecordingIndicatorHUDController.shared.hide()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CFinderPresentRecordingOverlay"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentRecordingRegionSelection()
        }
    }
    
    public func setupIPCListener() {
        DistributedNotificationCenter.default().addObserver(
            forName: IPCHelper.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let jsonStr = notif.userInfo?["payload"] as? String,
                  let data = jsonStr.data(using: .utf8),
                  let msg = try? JSONDecoder().decode(IPCMessage.self, from: data) else {
                return
            }
            Task { @MainActor in
                self?.handleMessage(msg)
            }
        }
    }
    
    public func handleMessage(_ message: IPCMessage) {
        let urls = message.targetPaths.map { URL(fileURLWithPath: $0) }
        
        switch message.actionType {
        case .showBatchRenameUI:
            presentBatchRename(urls: urls)
            
        case .scanVideoDuplicates:
            presentVideoTwinStudio(urls: urls)
            
        case .inspectVideo:
            presentVideoInspector(urls: urls)
            
        case .captureOCR:
            Task {
                _ = try? await ScreenOCREngine.shared.captureScreenInteractively()
            }
            
        case .undoBatchRename:
            do {
                if let reverted = try RenameUndoJournal.shared.undoLast(), !reverted.isEmpty {
                    showNotification(title: "CFinder — Hoàn tác thành công", message: "Đã khôi phục lại tên cũ cho \(reverted.count) tệp.")
                } else {
                    showNotification(title: "CFinder", message: "Không có thao tác đổi tên nào để hoàn tác.")
                }
            } catch {
                showNotification(title: "Lỗi hoàn tác", message: error.localizedDescription)
            }
            
        case .cutFiles:
            FinderCutManager.shared.cut(urls: urls)
            
        case .pasteFiles:
            let dest = urls.first
            FinderCutManager.shared.paste(to: dest)
            
        case .cancelCut:
            FinderCutManager.shared.cancelCut()
        }
    }
    
    public func presentBatchRename(urls: [URL]) {
        NSLog("[HostActionCoordinator] presentBatchRename called with %ld input URLs", urls.count)
        var targetURLs = urls
        
        // 1. If a single folder was explicitly passed, expand its contents
        if targetURLs.count == 1, let single = targetURLs.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: single.path, isDirectory: &isDir), isDir.boolValue {
                if let contents = try? FileManager.default.contentsOfDirectory(at: single, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    let files = contents.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    if !files.isEmpty {
                        targetURLs = files
                    }
                }
            }
        }
        
        self.currentRenameURLs = targetURLs
        
        if let existing = renameWindowController {
            self.renameWindowController = nil
            existing.window?.delegate = nil
            self.renameDelegate = nil
            existing.window?.orderOut(nil)
            existing.close()
        }
        
        NSApp.setActivationPolicy(.regular)
        let titleCount = targetURLs.isEmpty ? "Chọn tệp..." : "\(targetURLs.count) tệp"
        let contentView = BatchRenameView(urls: targetURLs) { [weak self] in
            self?.closeRenameWindow()
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.animationBehavior = .documentWindow
        window.title = "CFinder — Đổi tên hàng loạt (\(titleCount))"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        
        let delegate = WindowCloseDelegate()
        delegate.onClose = { [weak self] in
            self?.currentRenameURLs = []
            self?.renameWindowController = nil
            self?.renameDelegate = nil
            if self?.dashboardWindowController == nil && self?.settingsWindowController == nil && self?.historyWindowController == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        self.renameDelegate = delegate
        window.delegate = delegate
        
        let controller = NSWindowController(window: window)
        self.renameWindowController = controller
        
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closeRenameWindow() {
        guard let controller = renameWindowController else { return }
        self.renameWindowController = nil
        self.currentRenameURLs = []
        controller.window?.delegate = nil
        self.renameDelegate = nil
        controller.window?.orderOut(nil)
        controller.close()
        if self.dashboardWindowController == nil && self.settingsWindowController == nil && self.historyWindowController == nil && self.videoTwinWindowController == nil && self.videoInspectorWindowController == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - VideoTwin Duplicate Finder Studio
    
    public func presentVideoTwinStudio(urls: [URL]) {
        NSLog("[HostActionCoordinator] presentVideoTwinStudio called with %ld input URLs", urls.count)
        
        if let existing = videoTwinWindowController {
            self.videoTwinWindowController = nil
            existing.window?.delegate = nil
            self.videoTwinDelegate = nil
            existing.window?.orderOut(nil)
            existing.close()
        }
        
        NSApp.setActivationPolicy(.regular)
        let contentView = VideoTwinStudioView(urls: urls) { [weak self] in
            self?.closeVideoTwinStudio()
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 860, height: 580)
        window.center()
        window.animationBehavior = .documentWindow
        window.title = "CFinder — VideoTwin Studio (Tìm video trùng lặp)"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        
        let delegate = WindowCloseDelegate()
        delegate.onClose = { [weak self] in
            self?.videoTwinWindowController = nil
            self?.videoTwinDelegate = nil
            if self?.dashboardWindowController == nil && self?.settingsWindowController == nil && self?.historyWindowController == nil && self?.renameWindowController == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        self.videoTwinDelegate = delegate
        window.delegate = delegate
        
        let controller = NSWindowController(window: window)
        self.videoTwinWindowController = controller
        
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closeVideoTwinStudio() {
        guard let controller = videoTwinWindowController else { return }
        self.videoTwinWindowController = nil
        controller.window?.delegate = nil
        self.videoTwinDelegate = nil
        controller.window?.orderOut(nil)
        controller.close()
        if self.dashboardWindowController == nil && self.settingsWindowController == nil && self.historyWindowController == nil && self.renameWindowController == nil && self.videoInspectorWindowController == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - Video Inspector & Intelligent Comparator
    
    public func presentVideoInspector(urls: [URL]) {
        NSLog("[HostActionCoordinator] presentVideoInspector called with %ld input URLs", urls.count)
        var targetURLs = urls
        
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "ts", "flv", "wmv"]
        
        // If a single folder was passed, expand its contents to find all videos
        if targetURLs.count == 1, let single = targetURLs.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: single.path, isDirectory: &isDir), isDir.boolValue {
                if let contents = try? FileManager.default.contentsOfDirectory(at: single, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    let videos = contents.filter { videoExtensions.contains($0.pathExtension.lowercased()) }
                    if !videos.isEmpty {
                        targetURLs = videos
                    }
                }
            }
        }
        
        if let existing = videoInspectorWindowController {
            self.videoInspectorWindowController = nil
            existing.window?.delegate = nil
            self.videoInspectorDelegate = nil
            existing.window?.orderOut(nil)
            existing.close()
        }
        
        NSApp.setActivationPolicy(.regular)
        let contentView = VideoInspectorMasterView(urls: targetURLs) { [weak self] in
            self?.closeVideoInspector()
        }
        
        let count = max(2, targetURLs.count)
        let calcWidth = CGFloat(count) * 340 + 48
        let initialWidth: CGFloat = targetURLs.count >= 2 ? min(max(calcWidth, 1100), 1400) : 780
        let initialHeight: CGFloat = targetURLs.count >= 2 ? 740 : 640
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 800, height: 580)
        window.center()
        window.animationBehavior = .documentWindow
        window.title = targetURLs.count >= 2 ? "CFinder — Video Comparator (So sánh & Chấm điểm Video)" : "CFinder — Video Inspector (Thông số chi tiết Video)"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        
        let delegate = WindowCloseDelegate()
        delegate.onClose = { [weak self] in
            self?.videoInspectorWindowController = nil
            self?.videoInspectorDelegate = nil
            if self?.dashboardWindowController == nil && self?.settingsWindowController == nil && self?.historyWindowController == nil && self?.renameWindowController == nil && self?.videoTwinWindowController == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        self.videoInspectorDelegate = delegate
        window.delegate = delegate
        
        let controller = NSWindowController(window: window)
        self.videoInspectorWindowController = controller
        
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closeVideoInspector() {
        guard let controller = videoInspectorWindowController else { return }
        self.videoInspectorWindowController = nil
        controller.window?.delegate = nil
        self.videoInspectorDelegate = nil
        controller.window?.orderOut(nil)
        controller.close()
        if self.dashboardWindowController == nil && self.settingsWindowController == nil && self.historyWindowController == nil && self.renameWindowController == nil && self.videoTwinWindowController == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    public func presentDashboard(tab: DashboardTab? = nil) {
        NSLog("[HostActionCoordinator] presentDashboard called with tab: \(String(describing: tab))")
        NSApp.setActivationPolicy(.regular)
        if let existing = dashboardWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            if let tab = tab {
                NotificationCenter.default.post(name: DashboardView.switchTabNotification, object: tab)
            }
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "CFinder — Bảng điều khiển"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        
        let initialTab = tab ?? .overview
        let hostingView = NSHostingView(rootView: DashboardView(initialTab: initialTab))
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        
        let delegate = WindowCloseDelegate()
        delegate.onClose = { [weak self] in
            self?.dashboardWindowController = nil
            self?.dashboardDelegate = nil
            if self?.renameWindowController == nil && self?.settingsWindowController == nil && self?.historyWindowController == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        self.dashboardDelegate = delegate
        window.delegate = delegate
        
        let controller = NSWindowController(window: window)
        self.dashboardWindowController = controller
        
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func presentSettings() {
        if let existing = settingsWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 490),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "CFinder — Cài đặt hệ thống"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        
        let hostingView = NSHostingView(rootView: SettingsView())
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        
        let delegate = WindowCloseDelegate()
        delegate.onClose = { [weak self] in
            self?.settingsWindowController = nil
            self?.settingsDelegate = nil
        }
        self.settingsDelegate = delegate
        window.delegate = delegate
        
        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller
        
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func presentOCRHistory() {
        if let existing = historyWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "CFinder — Lịch sử quét OCR"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        
        let hostingView = NSHostingView(rootView: OCRHistoryView())
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        
        let delegate = WindowCloseDelegate()
        delegate.onClose = { [weak self] in
            self?.historyWindowController = nil
            self?.historyDelegate = nil
        }
        self.historyDelegate = delegate
        window.delegate = delegate
        
        let controller = NSWindowController(window: window)
        self.historyWindowController = controller
        
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func getFinderExplicitSelection() -> [URL] {
        let script = """
        tell application "Finder"
            set sel to selection
            if (count of sel) > 0 then
                set outPaths to {}
                repeat with f in sel
                    try
                        set end of outPaths to POSIX path of (f as alias)
                    end try
                end repeat
                return outPaths
            else
                return {}
            end if
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return [] }
        var errorDict: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorDict)
        if let err = errorDict {
            NSLog("[HostActionCoordinator] getFinderSelection AppleScript error: %@", err)
        }
        guard result.numberOfItems > 0 else { return [] }
        var urls: [URL] = []
        for i in 1...result.numberOfItems {
            if let str = result.atIndex(i)?.stringValue, !str.isEmpty {
                urls.append(URL(fileURLWithPath: str))
            }
        }
        NSLog("[HostActionCoordinator] getFinderSelection retrieved %ld URLs: %@", urls.count, urls)
        return urls
    }
    
    // MARK: - Hidden Windows Management for Clean Screen Capture
    private var hiddenWindowsForCapture: [NSWindow] = []
    
    public func hideAllWindowsForCapture() {
        var windowsToHide: [NSWindow] = []
        if let win = dashboardWindowController?.window, win.isVisible {
            windowsToHide.append(win)
        }
        if let win = settingsWindowController?.window, win.isVisible {
            windowsToHide.append(win)
        }
        if let win = historyWindowController?.window, win.isVisible {
            windowsToHide.append(win)
        }
        if let win = renameWindowController?.window, win.isVisible {
            windowsToHide.append(win)
        }
        if let win = videoTwinWindowController?.window, win.isVisible {
            windowsToHide.append(win)
        }
        if let win = videoInspectorWindowController?.window, win.isVisible {
            windowsToHide.append(win)
        }
        if EdgeNotesWindowController.shared.isVisible {
            EdgeNotesWindowController.shared.hideDrawer(force: true)
        }
        
        self.hiddenWindowsForCapture = windowsToHide
        for win in windowsToHide {
            win.orderOut(nil)
        }
    }
    
    public func restoreHiddenWindowsAfterCapture() {
        guard !hiddenWindowsForCapture.isEmpty else { return }
        for win in hiddenWindowsForCapture {
            win.makeKeyAndOrderFront(nil)
        }
        hiddenWindowsForCapture.removeAll()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func presentScrollingCapture() {
        hideAllWindowsForCapture()
        
        // Đợi 60ms để WindowServer macOS làm mới hoàn toàn nền màn hình bên dưới
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            ScrollingSelectionOverlayController.shared.presentOverlay(
                onCancelled: { [weak self] in
                    self?.restoreHiddenWindowsAfterCapture()
                }
            )
        }
    }
    
    public func presentRecordingRegionSelection() {
        hideAllWindowsForCapture()
        
        // Đợi 60ms để WindowServer macOS ẩn sạch các cửa sổ của app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            RecordingSelectionOverlayController.shared.presentOverlay(
                onConfirmRegion: { rect in
                    ScreenRecorderEngine.shared.startRecording(targetRect: rect)
                },
                onConfirmFullScreen: {
                    ScreenRecorderEngine.shared.startRecording(targetRect: nil)
                },
                onCancel: { [weak self] in
                    self?.restoreHiddenWindowsAfterCapture()
                }
            )
        }
    }
    
    public func showNotification(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
