import Foundation
import AppKit

public struct RenamePreviewItem: Identifiable, Sendable {
    public let id: UUID
    public let originalURL: URL
    public let originalName: String // e.g. "photo.JPG"
    public let originalBaseName: String // e.g. "photo"
    public let originalExtension: String // e.g. "JPG"
    public var newName: String // e.g. "img_01.jpg"
    public var targetURL: URL
    public var isChanged: Bool
    public var hasCollision: Bool
    public var collisionReason: String?
    public var fileSize: Int64
    public var isDirectory: Bool
    
    public init(
        id: UUID = UUID(),
        originalURL: URL,
        originalName: String,
        originalBaseName: String,
        originalExtension: String,
        newName: String,
        targetURL: URL,
        isChanged: Bool,
        hasCollision: Bool = false,
        collisionReason: String? = nil,
        fileSize: Int64 = 0,
        isDirectory: Bool = false
    ) {
        self.id = id
        self.originalURL = originalURL
        self.originalName = originalName
        self.originalBaseName = originalBaseName
        self.originalExtension = originalExtension
        self.newName = newName
        self.targetURL = targetURL
        self.isChanged = isChanged
        self.hasCollision = hasCollision
        self.collisionReason = collisionReason
        self.fileSize = fileSize
        self.isDirectory = isDirectory
    }
}
