import Foundation
import Combine

@MainActor
public final class QuickNotesStorage: ObservableObject {
    public static let shared = QuickNotesStorage()
    
    @Published public private(set) var notes: [QuickNoteItem] = []
    @Published public var currentNote: QuickNoteItem
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var lastSavedDate: Date? = nil
    
    private var saveDebounceTimer: Timer?
    private let fileURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CFinder/Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("notes.json")
        
        // Initial fallback note
        let defaultNote = QuickNoteItem(
            title: "Ghi chú nhanh",
            bodyText: "• Gõ là tự lưu\n• Rê chuột ra khỏi là tự ẩn\n• Đồng bộ iCloud với Apple Notes ",
            checklist: [
                QuickChecklistItem(text: "Rê chuột ra mép phải để mở ghi chú", isCompleted: true),
                QuickChecklistItem(text: "Bấm nút Ghim 📌 để giữ cửa sổ khi tra cứu tài liệu", isCompleted: false),
                QuickChecklistItem(text: "Bấm ↗ Apple Notes để mở trên iPhone/iPad", isCompleted: false)
            ],
            mode: .text
        )
        self.currentNote = defaultNote
        
        loadNotes()
        
        if notes.isEmpty {
            self.notes = [defaultNote]
            self.currentNote = defaultNote
            saveImmediately()
        } else if let first = notes.first {
            self.currentNote = first
        }
    }
    
    // MARK: - Persistence
    
    public func loadNotes() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([QuickNoteItem].self, from: data) else {
            return
        }
        self.notes = decoded
        if let lastActiveId = UserDefaults.standard.string(forKey: "CFinder_ActiveNoteId"),
           let match = decoded.first(where: { $0.id.uuidString == lastActiveId }) {
            self.currentNote = match
        } else if let first = decoded.first {
            self.currentNote = first
        }
    }
    
    public func requestAutoSave() {
        isSaving = true
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveImmediately()
            }
        }
    }
    
    public func saveImmediately() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil
        
        // Update currentNote inside notes array
        currentNote.updatedAt = Date()
        if let idx = notes.firstIndex(where: { $0.id == currentNote.id }) {
            notes[idx] = currentNote
        } else {
            notes.insert(currentNote, at: 0)
        }
        
        UserDefaults.standard.set(currentNote.id.uuidString, forKey: "CFinder_ActiveNoteId")
        
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: .atomic)
            self.lastSavedDate = Date()
            self.isSaving = false
            NSLog("[QuickNotesStorage] Note saved: id=%@ title=%@", currentNote.id.uuidString, currentNote.title)
        } catch {
            NSLog("[QuickNotesStorage] Failed to save notes: %@", error.localizedDescription)
            self.isSaving = false
        }
    }
    
    // MARK: - Actions
    
    public func createNewNote(mode: QuickNoteMode = .text) {
        saveImmediately()
        let newNote = QuickNoteItem(
            title: "Ghi chú mới",
            bodyText: "",
            checklist: [],
            mode: mode
        )
        notes.insert(newNote, at: 0)
        currentNote = newNote
        saveImmediately()
    }
    
    public func selectNote(_ note: QuickNoteItem) {
        saveImmediately()
        if let match = notes.first(where: { $0.id == note.id }) {
            self.currentNote = match
        }
    }
    
    public func deleteNote(_ note: QuickNoteItem) {
        notes.removeAll(where: { $0.id == note.id })
        if currentNote.id == note.id {
            if let first = notes.first {
                currentNote = first
            } else {
                createNewNote()
            }
        }
        saveImmediately()
    }
}
