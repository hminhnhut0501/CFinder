import Foundation

public struct RenameOperationEntry: Codable, Sendable {
    public let originalPath: String
    public let newPath: String
    public let timestamp: Date
    
    public init(originalPath: String, newPath: String, timestamp: Date = Date()) {
        self.originalPath = originalPath
        self.newPath = newPath
        self.timestamp = timestamp
    }
}

public struct RenameTransactionRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let entries: [RenameOperationEntry]
    public let summary: String
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), entries: [RenameOperationEntry], summary: String) {
        self.id = id
        self.timestamp = timestamp
        self.entries = entries
        self.summary = summary
    }
}
