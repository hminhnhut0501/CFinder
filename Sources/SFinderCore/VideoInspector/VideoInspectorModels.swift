import Foundation
import CoreMedia

// MARK: - Video Inspection Models

public enum BPPFHealth: String, Sendable, Hashable, Codable {
    case starved = "Thiếu Bitrate (Nén vỡ)"
    case optimal = "Chuẩn Tối ưu (Sắc nét & Tiết kiệm)"
    case high = "Bitrate Cao"
    case bloated = "Bơm Bitrate Ảo (Lãng phí dung lượng)"
    case excessiveBloat = "Phình Bitrate Nghiêm trọng"
    
    public var badgeColorHex: String {
        switch self {
        case .starved: return "EF4444" // Red
        case .optimal: return "10B981" // Green
        case .high: return "38BDF8"    // Sky Blue
        case .bloated: return "F59E0B" // Amber
        case .excessiveBloat: return "EF4444" // Red
        }
    }
}

public struct ScoreAdjustment: Sendable, Hashable, Codable, Identifiable {
    public var id: String { aspect + description }
    public let aspect: String
    public let description: String
    public let points: Double // positive or negative
    
    public init(aspect: String, description: String, points: Double) {
        self.aspect = aspect
        self.description = description
        self.points = points
    }
}

public struct VideoQualityScore: Sendable, Hashable, Codable {
    public let overallScore: Double       // 0...100
    public let visualFidelityScore: Double // 0...100
    public let storageEfficiencyScore: Double // 0...100
    public let audioFidelityScore: Double // 0...100
    public let bitsPerPixelFrame: Double
    public let bppfHealth: BPPFHealth
    public let adjustments: [ScoreAdjustment]
    public let verdictSummary: String
    public let isBloatedBitrate: Bool
    public let isSuspectedUpscale: Bool
    
    public init(
        overallScore: Double,
        visualFidelityScore: Double,
        storageEfficiencyScore: Double,
        audioFidelityScore: Double,
        bitsPerPixelFrame: Double,
        bppfHealth: BPPFHealth,
        adjustments: [ScoreAdjustment],
        verdictSummary: String,
        isBloatedBitrate: Bool,
        isSuspectedUpscale: Bool
    ) {
        self.overallScore = overallScore
        self.visualFidelityScore = visualFidelityScore
        self.storageEfficiencyScore = storageEfficiencyScore
        self.audioFidelityScore = audioFidelityScore
        self.bitsPerPixelFrame = bitsPerPixelFrame
        self.bppfHealth = bppfHealth
        self.adjustments = adjustments
        self.verdictSummary = verdictSummary
        self.isBloatedBitrate = isBloatedBitrate
        self.isSuspectedUpscale = isSuspectedUpscale
    }
}

public struct VideoStreamDetail: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(index)_\(codec)" }
    public let index: Int
    public let codec: String
    public let humanCodec: String
    public let profile: String?
    public let bitDepth: Int
    public let chromaSubsampling: String
    public let width: Int
    public let height: Int
    public let displayWidth: Int
    public let displayHeight: Int
    public let aspectRatio: String
    public let fps: Double
    public let isVFR: Bool
    public let bitrate: Int64
    public let isHDR: Bool
    public let colorPrimaries: String?
    public let transferCharacteristics: String?
    public let colorSpace: String?
    
    public init(
        index: Int,
        codec: String,
        humanCodec: String,
        profile: String?,
        bitDepth: Int,
        chromaSubsampling: String,
        width: Int,
        height: Int,
        displayWidth: Int,
        displayHeight: Int,
        aspectRatio: String,
        fps: Double,
        isVFR: Bool,
        bitrate: Int64,
        isHDR: Bool,
        colorPrimaries: String?,
        transferCharacteristics: String?,
        colorSpace: String?
    ) {
        self.index = index
        self.codec = codec
        self.humanCodec = humanCodec
        self.profile = profile
        self.bitDepth = bitDepth
        self.chromaSubsampling = chromaSubsampling
        self.width = width
        self.height = height
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.aspectRatio = aspectRatio
        self.fps = fps
        self.isVFR = isVFR
        self.bitrate = bitrate
        self.isHDR = isHDR
        self.colorPrimaries = colorPrimaries
        self.transferCharacteristics = transferCharacteristics
        self.colorSpace = colorSpace
    }
}

public struct AudioStreamDetail: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(index)_\(codec)" }
    public let index: Int
    public let codec: String
    public let humanCodec: String
    public let channels: Int
    public let channelLayout: String
    public let sampleRate: Double
    public let bitDepth: Int?
    public let bitrate: Int64?
    
    public init(
        index: Int,
        codec: String,
        humanCodec: String,
        channels: Int,
        channelLayout: String,
        sampleRate: Double,
        bitDepth: Int?,
        bitrate: Int64?
    ) {
        self.index = index
        self.codec = codec
        self.humanCodec = humanCodec
        self.channels = channels
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.bitrate = bitrate
    }
}

public struct VideoDetailedReport: Sendable, Hashable, Codable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let fileName: String
    public let fileSize: Int64
    public let container: String
    public let durationSeconds: Double
    public let totalBitrate: Int64
    public let videoStreams: [VideoStreamDetail]
    public let audioStreams: [AudioStreamDetail]
    public let creationDate: Date?
    public let score: VideoQualityScore
    
    public var primaryVideo: VideoStreamDetail? {
        videoStreams.first
    }
    
    public var primaryAudio: AudioStreamDetail? {
        audioStreams.first
    }
    
    public init(
        url: URL,
        fileName: String,
        fileSize: Int64,
        container: String,
        durationSeconds: Double,
        totalBitrate: Int64,
        videoStreams: [VideoStreamDetail],
        audioStreams: [AudioStreamDetail],
        creationDate: Date?,
        score: VideoQualityScore
    ) {
        self.url = url
        self.fileName = fileName
        self.fileSize = fileSize
        self.container = container
        self.durationSeconds = durationSeconds
        self.totalBitrate = totalBitrate
        self.videoStreams = videoStreams
        self.audioStreams = audioStreams
        self.creationDate = creationDate
        self.score = score
    }
}

public struct ComparisonVerdict: Sendable, Hashable, Codable {
    public let winnerURL: URL
    public let headline: String
    public let explanation: String
    public let storageDifferenceBytes: Int64
    public let isWinnerMoreEfficient: Bool
    
    public init(
        winnerURL: URL,
        headline: String,
        explanation: String,
        storageDifferenceBytes: Int64,
        isWinnerMoreEfficient: Bool
    ) {
        self.winnerURL = winnerURL
        self.headline = headline
        self.explanation = explanation
        self.storageDifferenceBytes = storageDifferenceBytes
        self.isWinnerMoreEfficient = isWinnerMoreEfficient
    }
}
