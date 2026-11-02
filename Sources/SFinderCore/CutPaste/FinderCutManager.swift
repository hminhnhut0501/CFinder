import Foundation
import AppKit
import Carbon
import AudioToolbox
import ApplicationServices

@MainActor
public final class FinderCutManager: ObservableObject {
    public static let shared = FinderCutManager()
    public static nonisolated let cutStateDidChangeNotification = Notification.Name("com.sfinder.cutStateDidChange")
    public static nonisolated let cutMarkerPasteboardType = NSPasteboard.PasteboardType("com.sfinder.cut-files")
    
    // MARK: - Published State
    @Published public private(set) var cutURLs: [URL] = []
    @Published public var isEnabled: Bool = true
    
    public var hasPendingCut: Bool {
        return !cutURLs.isEmpty
    }
    
    public var cutCount: Int {
        return cutURLs.count
    }
    
    public var onShowToast: ((_ icon: String, _ title: String, _ subtitle: String) -> Void)?
    
    // MARK: - CGEventTap Infrastructure
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private init() {
        // Load enabled preference
        self.isEnabled = UserDefaults.standard.object(forKey: "sfinder_enable_finder_cut") as? Bool ?? true
    }
    
    // MARK: - Cut Action
    
    public func cut(urls: [URL]) {
        let validURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !validURLs.isEmpty else { return }
        
        self.cutURLs = validURLs
        
        // Update general pasteboard so apps know files are on clipboard
        let pboard = NSPasteboard.general
        pboard.clearContents()
        pboard.writeObjects(validURLs as [NSURL])
        pboard.setString(String(Date().timeIntervalSince1970), forType: Self.cutMarkerPasteboardType)
        
        // Notify Finder extension and other listeners
        broadcastCutState()
        
        // Feedback
        AudioServicesPlaySystemSound(1104)
        let itemLabel = validURLs.count == 1 ? (validURLs.first?.lastPathComponent ?? "tệp") : "\(validURLs.count) mục"
        onShowToast?("scissors", "Đã cắt \(itemLabel) (⌘X)", "Mở thư mục mới rồi nhấn ⌘V để di chuyển")
        
        NSLog("[FinderCutManager] Cut %ld items: %@", validURLs.count, validURLs.map { $0.lastPathComponent }.joined(separator: ", "))
    }
    
    // MARK: - Paste Action (Move Files)
    
    public func paste(to targetFolder: URL? = nil) {
        guard hasPendingCut else { return }
        
        let destinationFolder: URL
        if let target = targetFolder {
            destinationFolder = target
        } else if let resolved = getFinderDestinationFolder() {
            destinationFolder = resolved
        } else {
            onShowToast?("exclamationmark.triangle", "Không tìm thấy thư mục đích", "Hãy nhấp vào thư mục bạn muốn dán")
            return
        }
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destinationFolder.path, isDirectory: &isDir), isDir.boolValue else {
            onShowToast?("exclamationmark.triangle", "Đích đến không hợp lệ", "Đường dẫn không phải là một thư mục")
            return
        }
        
        var movedCount = 0
        var errors: [String] = []
        let fm = FileManager.default
        let itemsToMove = self.cutURLs
        
        for src in itemsToMove {
            guard fm.fileExists(atPath: src.path) else { continue }
            
            // Check if source folder is the same as destination folder
            if src.deletingLastPathComponent().standardizedFileURL.path == destinationFolder.standardizedFileURL.path {
                NSLog("[FinderCutManager] Item already in destination: %@", src.lastPathComponent)
                continue
            }
            
            // Guard: Cannot move folder into itself or its own subfolder
            if destinationFolder.standardizedFileURL.path.hasPrefix(src.standardizedFileURL.path) {
                errors.append("Không thể di chuyển thư mục '\(src.lastPathComponent)' vào chính nó.")
                continue
            }
            
            let targetDest = destinationFolder.appendingPathComponent(src.lastPathComponent)
            let finalDest = uniqueDestinationURL(for: targetDest)
            
            do {
                try safeMoveItem(from: src, to: finalDest)
                movedCount += 1
            } catch {
                NSLog("[FinderCutManager] Failed to move %@: %@", src.path, error.localizedDescription)
                errors.append("\(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        // Clear cut state
        self.cutURLs = []
        broadcastCutState()
        
        // Notify Finder & system workspace of changes
        NSWorkspace.shared.noteFileSystemChanged(destinationFolder.path)
        for src in itemsToMove {
            NSWorkspace.shared.noteFileSystemChanged(src.deletingLastPathComponent().path)
        }
        refreshFinderDirectory(at: destinationFolder)
        
        // Sound and HUD feedback
        if movedCount > 0 {
            AudioServicesPlaySystemSound(1105)
            let folderName = destinationFolder.lastPathComponent.isEmpty ? "Thư mục đích" : destinationFolder.lastPathComponent
            onShowToast?("checkmark.circle.fill", "Đã di chuyển \(movedCount) mục (⌘V)", "Vào: \(folderName)")
        } else if let firstErr = errors.first {
            onShowToast?("exclamationmark.triangle.fill", "Lỗi di chuyển tệp", firstErr)
        } else {
            onShowToast?("info.circle", "Tệp đã ở vị trí này", "Không cần di chuyển thêm")
        }
    }
    
    // MARK: - Cancel Cut Action
    
    public func cancelCut() {
        guard hasPendingCut else { return }
        self.cutURLs = []
        broadcastCutState()
        NSLog("[FinderCutManager] Cut session cancelled")
    }
    
    // MARK: - Cross-Volume Safe Move
    
    private func safeMoveItem(from sourceURL: URL, to destURL: URL) throws {
        let fm = FileManager.default
        do {
            try fm.moveItem(at: sourceURL, to: destURL)
        } catch {
            // Fallback for cross-device / cross-volume links: Copy then Remove
            try fm.copyItem(at: sourceURL, to: destURL)
            try? fm.removeItem(at: sourceURL)
        }
    }
    
    // MARK: - Unique Destination URL Generator
    
    private func uniqueDestinationURL(for destURL: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destURL.path) else { return destURL }
        
        let dir = destURL.deletingLastPathComponent()
        let ext = destURL.pathExtension
        let base = destURL.deletingPathExtension().lastPathComponent
        
        var counter = 2
        while true {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let candidate = dir.appendingPathComponent(newName)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
    
    // MARK: - Broadcast Cut State
    
    private func broadcastCutState() {
        let paths = cutURLs.map { $0.path }
        DistributedNotificationCenter.default().postNotificationName(
            Self.cutStateDidChangeNotification,
            object: nil,
            userInfo: [
                "count": paths.count,
                "paths": paths
            ],
            deliverImmediately: true
        )
    }
    
    // MARK: - Finder Automation (AppleScript)
    
    public func getFinderSelection() -> [URL] {
        let script = """
        tell application "Finder"
            try
                set sel to selection as alias list
                set pList to {}
                repeat with f in sel
                    set end of pList to POSIX path of f
                end repeat
                return pList
            on error
                return {}
            end try
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return [] }
        let desc = appleScript.executeAndReturnError(&error)
        guard error == nil else { return [] }
        
        var urls: [URL] = []
        let count = desc.numberOfItems
        if count > 0 {
            for i in 1...count {
                if let str = desc.atIndex(i)?.stringValue, !str.isEmpty {
                    urls.append(URL(fileURLWithPath: str))
                }
            }
        } else if let single = desc.stringValue, !single.isEmpty {
            urls.append(URL(fileURLWithPath: single))
        }
        return urls
    }
    
    public func getFinderDestinationFolder() -> URL? {
        let script = """
        tell application "Finder"
            try
                set insLoc to (insertion location as alias)
                return POSIX path of insLoc
            on error
                return POSIX path of (path to desktop folder)
            end try
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        let desc = appleScript.executeAndReturnError(&error)
        guard error == nil, let path = desc.stringValue, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    private func refreshFinderDirectory(at folderURL: URL) {
        let script = """
        tell application "Finder"
            try
                update folder (POSIX file "\(folderURL.path)")
            end try
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
    
    // MARK: - Accessibility Text Edit Detection
    
    public nonisolated func isFocusedElementEditableText() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard appResult == .success, let app = focusedApp else { return false }
        
        var focusedElement: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard elemResult == .success, let element = focusedElement else { return false }
        
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
        let roleStr = role as? String ?? ""
        
        return roleStr == (kAXTextFieldRole as String) ||
               roleStr == (kAXTextAreaRole as String) ||
               roleStr == (kAXComboBoxRole as String)
    }
    
    // MARK: - Global CGEventTap Management
    
    public func startGlobalEventTap() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            NSLog("[FinderCutManager] Accessibility permission not granted for CGEventTap")
            return
        }
        
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let ref = refcon {
                    let manager = Unmanaged<FinderCutManager>.fromOpaque(ref).takeUnretainedValue()
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
                return Unmanaged.passRetained(event)
            }
            
            guard type == .keyDown else { return Unmanaged.passRetained(event) }
            
            // Fast frontmost check
            guard let frontApp = NSWorkspace.shared.frontmostApplication,
                  frontApp.bundleIdentifier == "com.apple.finder" else {
                return Unmanaged.passRetained(event)
            }
            
            guard let ref = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<FinderCutManager>.fromOpaque(ref).takeUnretainedValue()
            
            let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // 1. Check Command + X (Cut)
            if flags == .maskCommand && keyCode == 7 { // 7 is ANSI X
                if !manager.isFocusedElementEditableText() {
                    DispatchQueue.main.async {
                        manager.performCutFromFinder()
                    }
                    return nil // Intercept & swallow event
                }
            }
            // 2. Check Command + V (Paste/Move)
            else if flags == .maskCommand && keyCode == 9 { // 9 is ANSI V
                if manager.hasPendingCut && !manager.isFocusedElementEditableText() {
                    DispatchQueue.main.async {
                        manager.performPasteInFinder()
                    }
                    return nil // Intercept & swallow event
                }
            }
            // 3. Clear pending cut on Escape (53) or Command + C (8)
            else if (keyCode == 53 && flags.isEmpty) || (flags == .maskCommand && keyCode == 8) {
                if manager.hasPendingCut {
                    DispatchQueue.main.async {
                        manager.cancelCut()
                    }
                }
            }
            
            return Unmanaged.passRetained(event)
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            NSLog("[FinderCutManager] Failed to create CGEventTap for Finder Cut/Paste")
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[FinderCutManager] Global CGEventTap enabled for Finder ⌘X / ⌘V Cut & Paste!")
    }
    
    public func stopGlobalEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
            NSLog("[FinderCutManager] Global CGEventTap disabled")
        }
    }
    
    public func performCutFromFinder() {
        let sel = getFinderSelection()
        if !sel.isEmpty {
            cut(urls: sel)
        } else {
            NSLog("[FinderCutManager] ⌘X pressed in Finder but no files selected")
        }
    }
    
    public func performPasteInFinder() {
        paste(to: nil)
    }
}
