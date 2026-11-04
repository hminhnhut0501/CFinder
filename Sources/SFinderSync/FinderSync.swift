import Cocoa
import FinderSync
import SFinderCore

public class FinderSync: FIFinderSync {
    
    public override init() {
        super.init()
        NSLog("[SFinderSync] Extension initialized — Batch File Renamer for Finder")
        
        var monitored: Set<URL> = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/System/Volumes/Data"),
            URL(fileURLWithPath: "/Users"),
            URL(fileURLWithPath: NSHomeDirectory()),
            URL(fileURLWithPath: "/Volumes")
        ]
        
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let commonUserFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Work"]
        for folderName in commonUserFolders {
            let u = home.appendingPathComponent(folderName)
            if fm.fileExists(atPath: u.path) {
                monitored.insert(u)
            }
        }
        
        FIFinderSyncController.default().directoryURLs = monitored
        NSLog("[SFinderSync] Monitoring %ld directories for instant file selection", monitored.count)
        
        setupCutBadgeAndListener()
    }
    
    // MARK: - Cut Badge & State Listener
    
    private let cutBadgeIdentifier = "SFinderCutBadge"
    private var activeCutBadgedURLs: [URL] = []
    
    private func setupCutBadgeAndListener() {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        if let cutSymbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Đã cắt")?.withSymbolConfiguration(config) {
            FIFinderSyncController.default().setBadgeImage(cutSymbol, label: "Đã cắt", forBadgeIdentifier: cutBadgeIdentifier)
        }
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleCutStateChanged(_:)),
            name: FinderCutManager.cutStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleCutStateChanged(_ notif: Notification) {
        for url in activeCutBadgedURLs {
            FIFinderSyncController.default().setBadgeIdentifier("", for: url)
        }
        activeCutBadgedURLs.removeAll()
        
        guard let paths = notif.userInfo?["paths"] as? [String] else { return }
        for p in paths {
            let u = URL(fileURLWithPath: p)
            FIFinderSyncController.default().setBadgeIdentifier(cutBadgeIdentifier, for: u)
            activeCutBadgedURLs.append(u)
        }
    }
    
    private var hasCutFilesPending: Bool {
        return NSPasteboard.general.types?.contains(FinderCutManager.cutMarkerPasteboardType) == true
    }
    
    // MARK: - White Icon Generator (Pure White for macOS Liquid Glass)
    
    private func makeWhiteIcon(systemName: String) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            return NSImage()
        }
        
        let whiteImage = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        whiteImage.isTemplate = false
        return whiteImage
    }
    
    // MARK: - Toolbar Item Properties
    
    public override var toolbarItemName: String {
        return "CFinder"
    }
    
    public override var toolbarItemToolTip: String {
        return "CFinder: Đổi tên hàng loạt trên Finder"
    }
    
    public override var toolbarItemImage: NSImage {
        return BrandAssets.toolbarIcon(size: NSSize(width: 18, height: 18))
    }
    
    // MARK: - Menu Management (Direct 1-Action Click)
    
    public override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "CFinder")
        
        switch menuKind {
        case .contextualMenuForContainer:
            buildContainerMenu(into: menu)
            
        case .contextualMenuForItems:
            buildItemsMenu(into: menu)
            
        case .toolbarItemMenu:
            buildToolbarMenu(into: menu)
            
        case .contextualMenuForSidebar:
            return nil
            
        @unknown default:
            return nil
        }
        
        return menu
    }
    
    // MARK: - Container Menu (Right click on background / empty space)
    
    private func buildContainerMenu(into menu: NSMenu) {
        let containerURL = FIFinderSyncController.default().targetedURL()
        let containerPath = containerURL?.path ?? ""
        
        // Windows-style Paste option if files are currently cut
        if hasCutFilesPending {
            let pasteItem = NSMenuItem(title: "Dán tệp đã cắt vào đây (⌘V)", action: #selector(handlePasteFiles(_:)), keyEquivalent: "")
            pasteItem.image = makeWhiteIcon(systemName: "doc.on.clipboard")
            pasteItem.target = self
            pasteItem.representedObject = ["target": containerPath]
            menu.addItem(pasteItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        let renameItem = NSMenuItem(title: "Đổi tên hàng loạt trong thư mục này...", action: #selector(handleBatchRename(_:)), keyEquivalent: "")
        renameItem.image = makeWhiteIcon(systemName: "pencil.and.list.clipboard")
        renameItem.target = self
        renameItem.representedObject = ["targets": containerPath.isEmpty ? [] : [containerPath]]
        menu.addItem(renameItem)
        
        let videoTwinItem = NSMenuItem(title: "Tìm video trùng lặp trong thư mục này...", action: #selector(handleScanVideoDuplicates(_:)), keyEquivalent: "")
        videoTwinItem.image = makeWhiteIcon(systemName: "film.stack")
        videoTwinItem.target = self
        videoTwinItem.representedObject = ["targets": containerPath.isEmpty ? [] : [containerPath]]
        menu.addItem(videoTwinItem)
        
        let videoInspectItem = NSMenuItem(title: "So sánh & Chấm điểm video trong thư mục này...", action: #selector(handleInspectVideo(_:)), keyEquivalent: "")
        videoInspectItem.image = makeWhiteIcon(systemName: "arrow.left.and.right.circle")
        videoInspectItem.target = self
        videoInspectItem.representedObject = ["targets": containerPath.isEmpty ? [] : [containerPath]]
        menu.addItem(videoInspectItem)
        
        let undoItem = NSMenuItem(title: "Hoàn tác đổi tên lần trước", action: #selector(handleUndoRename(_:)), keyEquivalent: "")
        undoItem.image = makeWhiteIcon(systemName: "arrow.uturn.backward")
        undoItem.target = self
        menu.addItem(undoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let ocrItem = NSMenuItem(title: "Quét chữ màn hình (⌥C)", action: #selector(handleScreenOCR(_:)), keyEquivalent: "")
        ocrItem.image = makeWhiteIcon(systemName: "text.viewfinder")
        ocrItem.target = self
        menu.addItem(ocrItem)
    }
    
    // MARK: - Items Menu (Selected Files/Folders)
    
    private func buildItemsMenu(into menu: NSMenu) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty else {
            return
        }
        let paths = items.map { $0.path }
        
        // 1. Windows-style Cut files
        let cutTitle = items.count > 1 ? "Cắt \(items.count) tệp (⌘X)" : "Cắt tệp (⌘X)"
        let cutItem = NSMenuItem(title: cutTitle, action: #selector(handleCutFiles(_:)), keyEquivalent: "")
        cutItem.image = makeWhiteIcon(systemName: "scissors")
        cutItem.target = self
        cutItem.representedObject = ["targets": paths]
        menu.addItem(cutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let title = items.count > 1 ? "Đổi tên hàng loạt (\(items.count) mục)..." : "Đổi tên tệp..."
        let renameItem = NSMenuItem(title: title, action: #selector(handleBatchRename(_:)), keyEquivalent: "")
        renameItem.image = makeWhiteIcon(systemName: "pencil.and.list.clipboard")
        renameItem.target = self
        renameItem.representedObject = ["targets": paths]
        menu.addItem(renameItem)
        
        let vtTitle = items.count > 1 ? "Tìm video trùng lặp (\(items.count) mục)..." : "Tìm video trùng lặp..."
        let videoTwinItem = NSMenuItem(title: vtTitle, action: #selector(handleScanVideoDuplicates(_:)), keyEquivalent: "")
        videoTwinItem.image = makeWhiteIcon(systemName: "film.stack")
        videoTwinItem.target = self
        videoTwinItem.representedObject = ["targets": paths]
        menu.addItem(videoTwinItem)
        
        // Video Inspector / Intelligent Comparator
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "ts", "flv", "wmv"]
        let videoItems = items.filter { videoExtensions.contains($0.pathExtension.lowercased()) }
        if !videoItems.isEmpty {
            let inspectTitle = videoItems.count > 1 ? "So sánh & Chấm điểm video (\(videoItems.count) video)..." : "Xem thông số chi tiết video..."
            let inspectIcon = videoItems.count > 1 ? "arrow.left.and.right.circle" : "info.circle"
            let inspectItem = NSMenuItem(title: inspectTitle, action: #selector(handleInspectVideo(_:)), keyEquivalent: "")
            inspectItem.image = makeWhiteIcon(systemName: inspectIcon)
            inspectItem.target = self
            inspectItem.representedObject = ["targets": videoItems.map { $0.path }]
            menu.addItem(inspectItem)
        }
        
        let undoItem = NSMenuItem(title: "Hoàn tác đổi tên lần trước", action: #selector(handleUndoRename(_:)), keyEquivalent: "")
        undoItem.image = makeWhiteIcon(systemName: "arrow.uturn.backward")
        undoItem.target = self
        menu.addItem(undoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let ocrItem = NSMenuItem(title: "Quét chữ màn hình (⌥C)", action: #selector(handleScreenOCR(_:)), keyEquivalent: "")
        ocrItem.image = makeWhiteIcon(systemName: "text.viewfinder")
        ocrItem.target = self
        menu.addItem(ocrItem)
    }
    
    // MARK: - Toolbar Menu (Clicking Toolbar Icon)
    
    private func buildToolbarMenu(into menu: NSMenu) {
        if let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty {
            buildItemsMenu(into: menu)
        } else {
            buildContainerMenu(into: menu)
        }
    }
    
    // MARK: - Actions
    
    @objc private func handleBatchRename(_ sender: NSMenuItem) {
        var targets = (sender.representedObject as? [String: Any])?["targets"] as? [String] ?? []
        
        // Always check selectedItemURLs at click time if targets is empty or a single folder
        if targets.isEmpty || (targets.count == 1 && (try? URL(fileURLWithPath: targets[0]).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true) {
            if let currentSelection = FIFinderSyncController.default().selectedItemURLs(), !currentSelection.isEmpty {
                targets = currentSelection.map { $0.path }
            }
        }
        
        NSLog("[SFinderSync] handleBatchRename sending %ld targets to Studio", targets.count)
        let msg = IPCMessage(actionType: .showBatchRenameUI, targetPaths: targets)
        try? IPCHelper.shared.send(message: msg)
    }
    
    @objc private func handleScanVideoDuplicates(_ sender: NSMenuItem) {
        var targets = (sender.representedObject as? [String: Any])?["targets"] as? [String] ?? []
        
        // Always check selectedItemURLs at click time if targets is empty or a single folder
        if targets.isEmpty || (targets.count == 1 && (try? URL(fileURLWithPath: targets[0]).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true) {
            if let currentSelection = FIFinderSyncController.default().selectedItemURLs(), !currentSelection.isEmpty {
                targets = currentSelection.map { $0.path }
            }
        }
        
        NSLog("[SFinderSync] handleScanVideoDuplicates sending %ld targets to VideoTwin Studio", targets.count)
        let msg = IPCMessage(actionType: .scanVideoDuplicates, targetPaths: targets)
        try? IPCHelper.shared.send(message: msg)
    }
    
    @objc private func handleInspectVideo(_ sender: NSMenuItem) {
        var targets = (sender.representedObject as? [String: Any])?["targets"] as? [String] ?? []
        if targets.isEmpty {
            if let currentSelection = FIFinderSyncController.default().selectedItemURLs(), !currentSelection.isEmpty {
                targets = currentSelection.map { $0.path }
            }
        }
        NSLog("[SFinderSync] handleInspectVideo sending %ld targets to Video Inspector", targets.count)
        let msg = IPCMessage(actionType: .inspectVideo, targetPaths: targets)
        try? IPCHelper.shared.send(message: msg)
    }
    
    @objc private func handleUndoRename(_ sender: NSMenuItem) {
        let msg = IPCMessage(actionType: .undoBatchRename)
        try? IPCHelper.shared.send(message: msg)
    }
    
    @objc private func handleScreenOCR(_ sender: NSMenuItem) {
        let msg = IPCMessage(actionType: .captureOCR)
        try? IPCHelper.shared.send(message: msg)
    }
    
    @objc private func handleCutFiles(_ sender: NSMenuItem) {
        let targets = (sender.representedObject as? [String: Any])?["targets"] as? [String] ?? []
        guard !targets.isEmpty else { return }
        let msg = IPCMessage(actionType: .cutFiles, targetPaths: targets)
        try? IPCHelper.shared.send(message: msg)
    }
    
    @objc private func handlePasteFiles(_ sender: NSMenuItem) {
        let target = (sender.representedObject as? [String: Any])?["target"] as? String ?? ""
        let targets = target.isEmpty ? [] : [target]
        let msg = IPCMessage(actionType: .pasteFiles, targetPaths: targets)
        try? IPCHelper.shared.send(message: msg)
    }
}
