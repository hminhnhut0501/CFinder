import Foundation
import CoreMedia

/// Complete metadata for a video file.
public struct VideoMetadata: Sendable, Hashable, Codable {
    // MARK: - Container
    public let container: String
    public let fileSize: Int64
    public let creationDate: Date?
    public let modificationDate: Date?

    // MARK: - Video Stream
    public let videoStream: VideoStreamMetadata?

    // MARK: - Audio Stream
    public let audioStream: AudioStreamMetadata?

    // MARK: - Computed
    public var duration: CMTime {
        guard let d = videoStream?.duration else { return .zero }
        return d
    }

    public var durationSeconds: Double {
        CMTimeGetSeconds(duration)
    }
}

public struct VideoStreamMetadata: Sendable, Hashable, Codable {
    public let codec: String
    public let codecProfile: String?
    public let codecLevel: String?
    public let pixelFormat: String?
    public let bitDepth: Int?
    public let width: Int
    public let height: Int
    /// Display dimensions (after rotation/SAR)
    public let displayWidth: Int
    public let displayHeight: Int
    public let rotation: Double
    public let nominalFPS: Double
    public let averageFPS: Double?
    public let isVFR: Bool
    public let bitrate: Int64?
    public let isHDR: Bool
    public let colorPrimaries: String?
    public let transferCharacteristics: String?
    public let colorSpace: String?
    public let duration: CMTime

    public var aspectRatio: Double {
        guard displayHeight > 0 else { return 0 }
        return Double(displayWidth) / Double(displayHeight)
    }

    public var isLandscape: Bool { displayWidth >= displayHeight }

    /// Resolution family bucket for candidate generation
    public var resolutionFamily: ResolutionFamily {
        let longEdge = max(displayWidth, displayHeight)
        switch longEdge {
        case ..<480: return .sub480p
        case 480..<720: return .p480
        case 720..<1080: return .p720
        case 1080..<1440: return .p1080
        case 1440..<2160: return .p1440
        case 2160...: return .p4K
        default: return .unknown
        }
    }
}

public struct AudioStreamMetadata: Sendable, Hashable, Codable {
    public let codec: String
    public let channels: Int
    public let sampleRate: Double
    public let bitrate: Int64?
}

public enum ResolutionFamily: String, Sendable, Hashable, Codable, CaseIterable {
    case sub480p, p480, p720, p1080, p1440, p4K, unknown
}

/// CMTime Codable support
extension CMTime: @retroactive Codable {
    public enum CodingKeys: String, CodingKey { case value, timescale }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let value = try c.decode(Int64.self, forKey: .value)
        let timescale = try c.decode(Int32.self, forKey: .timescale)
        self.init(value: value, timescale: timescale)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
        try c.encode(timescale, forKey: .timescale)
    }
}
