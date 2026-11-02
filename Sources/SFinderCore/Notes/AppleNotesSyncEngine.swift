import Foundation
import AppKit

@MainActor
public final class AppleNotesSyncEngine: ObservableObject {
    public static let shared = AppleNotesSyncEngine()
    
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date? = nil
    @Published public private(set) var syncStatusText: String = "Lưu cục bộ"
    
    @Published public var isAutoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSyncEnabled, forKey: "CFinder_SyncWithAppleNotes")
        }
    }
    
    private var syncDebounceTimer: Timer?
    
    private init() {
        if UserDefaults.standard.object(forKey: "CFinder_SyncWithAppleNotes") == nil {
            self.isAutoSyncEnabled = true
        } else {
            self.isAutoSyncEnabled = UserDefaults.standard.bool(forKey: "CFinder_SyncWithAppleNotes")
        }
    }
    
    // MARK: - Debounced Trigger
    
    public func requestSync(note: QuickNoteItem) {
        guard isAutoSyncEnabled else {
            self.syncStatusText = "Lưu cục bộ (Tắt sync )"
            return
        }
        
        syncDebounceTimer?.invalidate()
        syncDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performSync(note: note)
            }
        }
    }
    
    // MARK: - Sync Implementation
    
    public func performSync(note: QuickNoteItem) {
        guard isAutoSyncEnabled else { return }
        self.isSyncing = true
        self.syncStatusText = "Đang đồng bộ  Notes..."
        
        let titleSafe = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ghi chú CFinder" : note.title
        let noteUUID = note.id.uuidString
        let appleNoteId = note.appleNotesId ?? ""
        let metaTag = "<div style=\"display:none;\">cfinder-id:\(noteUUID)</div>"
        
        var bodyContent = ""
        if note.mode == .checklist {
            var itemsHtml = ""
            for item in note.checklist {
                let mark = item.isCompleted ? "☑" : "☐"
                itemsHtml += "<p>\(mark) \(escapeHtml(item.text))</p>"
            }
            bodyContent = "<h1>\(escapeHtml(titleSafe))</h1>\(itemsHtml)<p><small>CFinder • \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))</small></p>\(metaTag)"
        } else {
            let lines = note.bodyText.components(separatedBy: "\n")
            let formattedLines = lines.map { "<p>\(escapeHtml($0))</p>" }.joined()
            bodyContent = "<h1>\(escapeHtml(titleSafe))</h1>\(formattedLines)<p><small>CFinder • \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))</small></p>\(metaTag)"
        }
        
        // Execute background AppleScript with unique ID binding (never creates duplicate notes on title change)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let script = """
            on run argv
                set noteAppleId to item 1 of argv
                set noteHtml to item 2 of argv
                set cfinderUUID to item 3 of argv
                with timeout of 4 seconds
                    tell application "Notes"
                        set targetFolderName to "CFinder Quick Notes"
                        tell default account
                            if not (exists folder targetFolderName) then
                                make new folder with properties {name:targetFolderName}
                            end if
                            set targetFolder to folder targetFolderName
                            
                            set foundNote to missing value
                            
                            -- Step 1: Lookup by Apple Notes unique ID
                            if noteAppleId is not "" then
                                try
                                    set foundNote to note id noteAppleId
                                end try
                            end if
                            
                            -- Step 2: Lookup by immutable CFinder UUID embedded in note body
                            if foundNote is missing value and cfinderUUID is not "" then
                                set matchTag to "cfinder-id:" & cfinderUUID
                                repeat with n in notes of targetFolder
                                    try
                                        if (body of n) contains matchTag then
                                            set foundNote to n
                                            exit repeat
                                        end if
                                    end try
                                end repeat
                            end if
                            
                            -- Step 3: Update existing note body OR create brand new note
                            if foundNote is not missing value then
                                set body of foundNote to noteHtml
                                return id of foundNote
                            else
                                set newNote to make new note at targetFolder with properties {body:noteHtml}
                                return id of newNote
                            end if
                        end tell
                    end tell
                end timeout
            end run
            """
            
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script, appleNoteId, bodyContent, noteUUID]
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                let success = (process.terminationStatus == 0)
                
                var returnedId = ""
                if success {
                    let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                    returnedId = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isSyncing = false
                    if success {
                        self.lastSyncDate = Date()
                        self.syncStatusText = "Đã đồng bộ  Notes"
                        if !returnedId.isEmpty {
                            QuickNotesStorage.shared.updateAppleNotesId(for: note.id, appleNotesId: returnedId)
                        }
                        NSLog("[AppleNotesSyncEngine] Synced note '%@' (UUID: %@, AppleID: %@)", titleSafe, noteUUID, returnedId)
                    } else {
                        self.syncStatusText = "Lưu cục bộ ( Notes chờ quyền)"
                        NSLog("[AppleNotesSyncEngine] AppleScript exited with code %d", process.terminationStatus)
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isSyncing = false
                    self.syncStatusText = "Lưu cục bộ"
                }
            }
        }
    }
    
    // MARK: - Delete Note from Apple Notes
    
    public func deleteNoteFromAppleNotes(appleNotesId: String?) {
        guard let noteId = appleNotesId, !noteId.isEmpty, isAutoSyncEnabled else { return }
        
        DispatchQueue.global(qos: .utility).async {
            let script = """
            on run argv
                set noteAppleId to item 1 of argv
                with timeout of 3 seconds
                    tell application "Notes"
                        try
                            set n to note id noteAppleId
                            delete n
                        end try
                    end tell
                end timeout
            end run
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script, noteId]
            try? process.run()
            process.waitUntilExit()
        }
    }
    
    // MARK: - Open Notes.app
    
    public func openAppleNotesApp() {
        if let notesUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: notesUrl, configuration: config, completionHandler: nil)
        }
    }
    
    private func escapeHtml(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
