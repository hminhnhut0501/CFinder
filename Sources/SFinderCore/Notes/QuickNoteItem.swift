import Foundation

public enum QuickNoteMode: String, Codable, Sendable {
    case text
    case checklist
}

public struct QuickChecklistItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var isCompleted: Bool
    
    public init(id: UUID = UUID(), text: String, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }
}

public struct QuickNoteItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var bodyText: String
    public var checklist: [QuickChecklistItem]
    public var mode: QuickNoteMode
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var appleNotesId: String?
    
    public init(
        id: UUID = UUID(),
        title: String = "",
        bodyText: String = "",
        checklist: [QuickChecklistItem] = [],
        mode: QuickNoteMode = .text,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        appleNotesId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.checklist = checklist
        self.mode = mode
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.appleNotesId = appleNotesId
    }
    
    public var wordCount: Int {
        if mode == .text {
            let words = bodyText.split { $0.isWhitespace || $0.isNewline }
            return words.count
        } else {
            let total = checklist.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            return total
        }
    }
    
    public var charCount: Int {
        if mode == .text {
            return bodyText.count
        } else {
            return checklist.reduce(0) { $0 + $1.text.count }
        }
    }
    
    public var completedChecklistCount: Int {
        checklist.filter { $0.isCompleted }.count
    }
}
