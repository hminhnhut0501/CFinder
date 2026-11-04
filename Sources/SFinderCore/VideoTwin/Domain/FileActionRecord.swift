import Foundation

public struct FileActionRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let asset: VideoAsset
    public let keeper: VideoAsset?
    public let createdAt: Date
}
