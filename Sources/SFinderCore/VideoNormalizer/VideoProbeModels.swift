import Foundation

public struct VideoStreamInfo: Sendable, Codable {
    public let index: Int
    public let codecName: String
    public let profile: String?
    public let width: Int
    public let height: Int
    public let fps: Double
    public let pixFmt: String
    public let colorSpace: String?
    public let colorTransfer: String?
    public let colorPrimaries: String?
    public let isHDR: Bool
    public let bitRate: Int64
    
    public var aspectRatio: Double {
        guard height > 0 else { return 1.0 }
        return Double(width) / Double(height)
    }
    
    public var isPortrait: Bool {
        return height > width
    }
    
    public var maxDimension: Int {
        return max(width, height)
    }
    
    public var isCompliantH264: Bool {
        return codecName.lowercased() == "h264" && pixFmt.lowercased() == "yuv420p" && !isHDR
    }
}

public struct AudioStreamInfo: Sendable, Codable {
    public let index: Int
    public let codecName: String
    public let channels: Int
    public let channelLayout: String?
    public let sampleRate: Int
    public let bitRate: Int64
    
    public var isCompliantAAC: Bool {
        return codecName.lowercased() == "aac" && channels <= 2
    }
}

public struct VideoProbeResult: Sendable {
    public let fileURL: URL
    public let fileSize: Int64
    public let duration: Double
    public let overallBitrate: Int64
    public let formatName: String
    public let isFastStart: Bool
    public let videoStream: VideoStreamInfo?
    public let audioStream: AudioStreamInfo?
    public let allVideoStreams: [VideoStreamInfo]
    public let allAudioStreams: [AudioStreamInfo]
    
    public var hasVideo: Bool { videoStream != nil }
    public var hasAudio: Bool { audioStream != nil }
}

public struct NormalizationPlan: Sendable {
    public enum Strategy: Sendable {
        /// Video is already in perfect H.264 + AAC stereo + faststart format with optimal bitrate. No processing required!
        case alreadyOptimal
        /// Audio & Video codecs and bitrate are already compliant, but moov atom is at the end or container is MKV/MOV. Fast remux (< 1s).
        case remuxFastStart
        /// Video requires re-encoding (e.g. HEVC/AV1/VP9, HDR tone-mapping, resolution clamp, or downmix 5.1/7.1 audio).
        case transcode
    }
    
    public let strategy: Strategy
    public let sourceInfo: VideoProbeResult
    public let targetWidth: Int
    public let targetHeight: Int
    public let targetVideoBitrate: Int64
    public let targetAudioBitrate: Int64
    public let needsToneMapping: Bool
    public let needsAudioDownmix: Bool
    public let encoder: String
    public let summary: String
}
