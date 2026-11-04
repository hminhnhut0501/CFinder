import Foundation

/// Compact audio fingerprint for a video.
public struct AudioFingerprint: Sendable, Hashable, Codable {
    public let assetID: UUID
    /// Fingerprint data (e.g. Chromaprint-style or custom)
    public let fingerprint: [UInt8]
    public let durationSeconds: Double
    public let algorithmVersion: String
}
