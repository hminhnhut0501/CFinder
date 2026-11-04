import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import OSLog

public actor VideoInspectorEngine {
    public static let shared = VideoInspectorEngine()
    private let logger = Logger(subsystem: "com.sfinder.videoinspector", category: "engine")
    private let scorer = VideoScoringEngine()
    
    public init() {}
    
    // MARK: - Inspect API
    
    public func inspect(url: URL) async -> VideoDetailedReport? {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        
        let fileAttrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (fileAttrs?[.size] as? Int64) ?? 0
        let creationDate = fileAttrs?[.creationDate] as? Date
        let container = url.pathExtension.uppercased()
        
        // Duration
        var durationSeconds: Double = 0
        if let d = try? await asset.load(.duration) {
            durationSeconds = CMTimeGetSeconds(d)
        }
        
        // Video Tracks
        var videoStreams: [VideoStreamDetail] = []
        if let vTracks = try? await asset.loadTracks(withMediaType: .video) {
            for (idx, track) in vTracks.enumerated() {
                if let vDetail = await probeVideoTrack(track, index: idx, asset: asset, fileSize: fileSize, durationSeconds: durationSeconds) {
                    videoStreams.append(vDetail)
                }
            }
        }
        
        // Audio Tracks
        var audioStreams: [AudioStreamDetail] = []
        if let aTracks = try? await asset.loadTracks(withMediaType: .audio) {
            for (idx, track) in aTracks.enumerated() {
                if let aDetail = await probeAudioTrack(track, index: idx) {
                    audioStreams.append(aDetail)
                }
            }
        }
        
        guard !videoStreams.isEmpty || !audioStreams.isEmpty else {
            return nil
        }
        
        // Total Bitrate
        let totalBitrate: Int64 = durationSeconds > 0 ? Int64((Double(fileSize) * 8.0) / durationSeconds) : 0
        
        // Quality & Efficiency Score
        let score = scorer.scoreVideo(
            fileSize: fileSize,
            durationSeconds: durationSeconds,
            video: videoStreams.first,
            audio: audioStreams.first
        )
        
        return VideoDetailedReport(
            url: url,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            container: container,
            durationSeconds: durationSeconds,
            totalBitrate: totalBitrate,
            videoStreams: videoStreams,
            audioStreams: audioStreams,
            creationDate: creationDate,
            score: score
        )
    }
    
    public func inspectBatch(urls: [URL]) async -> [VideoDetailedReport] {
        await withTaskGroup(of: (Int, VideoDetailedReport?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let rep = await self.inspect(url: url)
                    return (index, rep)
                }
            }
            var indexed: [(Int, VideoDetailedReport)] = []
            for await (idx, rep) in group {
                if let rep {
                    indexed.append((idx, rep))
                }
            }
            indexed.sort { $0.0 < $1.0 }
            return indexed.map { $0.1 }
        }
    }
    
    // MARK: - Video Track Probe
    
    private func probeVideoTrack(
        _ track: AVAssetTrack,
        index: Int,
        asset: AVURLAsset,
        fileSize: Int64,
        durationSeconds: Double
    ) async -> VideoStreamDetail? {
        do {
            let nominalFPS = try await track.load(.nominalFrameRate)
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            var estimatedBitrate = try await track.load(.estimatedDataRate)
            
            if estimatedBitrate <= 0 && durationSeconds > 0 {
                estimatedBitrate = Float((Double(fileSize) * 8.0 * 0.90) / durationSeconds)
            }
            
            // Display dimensions after rotation/SAR
            let displaySize = naturalSize.applying(preferredTransform)
            let displayWidth = abs(Int(displaySize.width.rounded()))
            let displayHeight = abs(Int(displaySize.height.rounded()))
            
            let width = Int(naturalSize.width.rounded())
            let height = Int(naturalSize.height.rounded())
            
            // Format descriptions
            let formatDescriptions = try await track.load(.formatDescriptions)
            var rawCodec = "unknown"
            var humanCodec = "Không rõ"
            var isHDR = false
            var bitDepth = 8
            var colorPrimaries: String?
            var transferCharacteristics: String?
            var chromaSubsampling = "4:2:0"
            
            if let desc = formatDescriptions.first {
                let subType = CMFormatDescriptionGetMediaSubType(desc)
                rawCodec = fourCCToString(subType)
                humanCodec = humanReadableCodec(rawCodec)
                
                let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any]
                transferCharacteristics = extensions?[kCMFormatDescriptionExtension_TransferFunction as String] as? String
                colorPrimaries = extensions?[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
                
                if let tc = transferCharacteristics {
                    let tcLower = tc.lowercased()
                    isHDR = tcLower.contains("2084") || tcLower.contains("2100") || tcLower.contains("hlg") || tcLower.contains("arib")
                }
                
                if let depth = extensions?[kCMFormatDescriptionExtension_Depth as String] as? Int, depth > 8 {
                    bitDepth = depth
                } else if isHDR {
                    bitDepth = 10
                }
                
                if let chroma = extensions?[kCMFormatDescriptionExtension_ChromaLocationTopField as String] as? String {
                    if chroma.contains("422") { chromaSubsampling = "4:2:2" }
                    else if chroma.contains("444") { chromaSubsampling = "4:4:4" }
                }
            }
            
            // Aspect ratio calculation
            let arGCD = gcd(displayWidth > 0 ? displayWidth : width, displayHeight > 0 ? displayHeight : height)
            let arW = (displayWidth > 0 ? displayWidth : width) / max(1, arGCD)
            let arH = (displayHeight > 0 ? displayHeight : height) / max(1, arGCD)
            let arStr = (arW <= 32 && arH <= 32) ? "\(arW):\(arH)" : String(format: "%.2f:1", Double(displayWidth) / Double(max(1, displayHeight)))
            
            return VideoStreamDetail(
                index: index,
                codec: rawCodec,
                humanCodec: humanCodec,
                profile: nil,
                bitDepth: bitDepth,
                chromaSubsampling: chromaSubsampling,
                width: width,
                height: height,
                displayWidth: displayWidth > 0 ? displayWidth : width,
                displayHeight: displayHeight > 0 ? displayHeight : height,
                aspectRatio: arStr,
                fps: Double(nominalFPS),
                isVFR: false,
                bitrate: Int64(estimatedBitrate),
                isHDR: isHDR,
                colorPrimaries: cleanColorString(colorPrimaries),
                transferCharacteristics: cleanColorString(transferCharacteristics),
                colorSpace: nil
            )
        } catch {
            logger.warning("Error probing video track: \(error)")
            return nil
        }
    }
    
    // MARK: - Audio Track Probe
    
    private func probeAudioTrack(_ track: AVAssetTrack, index: Int) async -> AudioStreamDetail? {
        do {
            let estimatedBitrate = try await track.load(.estimatedDataRate)
            let formatDescriptions = try await track.load(.formatDescriptions)
            
            var rawCodec = "unknown"
            var humanCodec = "Âm thanh"
            var channels = 2
            var sampleRate: Double = 48000
            var bitDepth: Int? = 16
            
            if let desc = formatDescriptions.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                sampleRate = asbd.pointee.mSampleRate
                channels = Int(asbd.pointee.mChannelsPerFrame)
                let subType = CMFormatDescriptionGetMediaSubType(desc)
                rawCodec = fourCCToString(subType)
                humanCodec = humanReadableAudioCodec(rawCodec)
                
                if asbd.pointee.mBitsPerChannel > 0 {
                    bitDepth = Int(asbd.pointee.mBitsPerChannel)
                }
            }
            
            let layoutDesc: String
            switch channels {
            case 1: layoutDesc = "Mono (1.0)"
            case 2: layoutDesc = "Stereo (2.0)"
            case 6: layoutDesc = "5.1 Surround"
            case 8: layoutDesc = "7.1 Atmos / Surround"
            default: layoutDesc = "\(channels) kênh"
            }
            
            return AudioStreamDetail(
                index: index,
                codec: rawCodec,
                humanCodec: humanCodec,
                channels: channels,
                channelLayout: layoutDesc,
                sampleRate: sampleRate,
                bitDepth: bitDepth,
                bitrate: estimatedBitrate > 0 ? Int64(estimatedBitrate) : nil
            )
        } catch {
            logger.warning("Error probing audio track: \(error)")
            return nil
        }
    }
    
    // MARK: - Helpers
    
    private func fourCCToString(_ fourCC: FourCharCode) -> String {
        let bytes = [
            UInt8((fourCC >> 24) & 0xFF),
            UInt8((fourCC >> 16) & 0xFF),
            UInt8((fourCC >> 8) & 0xFF),
            UInt8(fourCC & 0xFF)
        ]
        return (String(bytes: bytes, encoding: .ascii) ?? "????").trimmingCharacters(in: .whitespaces)
    }
    
    private func humanReadableCodec(_ c: String) -> String {
        let low = c.lowercased()
        if low.contains("hvc1") || low.contains("hev1") || low.contains("hevc") { return "HEVC / H.265" }
        if low.contains("avc1") || low.contains("h264") { return "H.264 / AVC" }
        if low.contains("av01") || low.contains("av1") { return "AV1" }
        if low.contains("vp09") || low.contains("vp9") { return "VP9" }
        if low.contains("apcn") { return "Apple ProRes 422" }
        if low.contains("apch") { return "Apple ProRes 422 HQ" }
        if low.contains("ap4h") { return "Apple ProRes 4444" }
        if low.contains("prores") { return "Apple ProRes" }
        if low.contains("mp4v") { return "MPEG-4 Part 2" }
        return c.uppercased()
    }
    
    private func humanReadableAudioCodec(_ c: String) -> String {
        let low = c.lowercased()
        if low.contains("aac") || low.contains("mp4a") { return "AAC" }
        if low.contains("ac-3") || low.contains("ac3") { return "Dolby Digital (AC-3)" }
        if low.contains("ec-3") || low.contains("eac3") { return "Dolby Digital Plus (E-AC-3)" }
        if low.contains("flac") { return "FLAC Lossless" }
        if low.contains("alac") { return "Apple Lossless (ALAC)" }
        if low.contains("lpcm") || low.contains("pcm") { return "PCM Không nén" }
        if low.contains("opus") { return "Opus" }
        if low.contains(".mp3") || low.contains("mp3") { return "MP3" }
        return c.uppercased()
    }
    
    private func cleanColorString(_ s: String?) -> String? {
        guard let s else { return nil }
        let low = s.lowercased()
        if low.contains("2020") { return "ITU-R BT.2020" }
        if low.contains("709") { return "ITU-R BT.709" }
        if low.contains("p3") { return "DCI-P3" }
        if low.contains("2084") || low.contains("pq") { return "HDR10 (PQ)" }
        if low.contains("hlg") { return "HLG HDR" }
        return s.components(separatedBy: "_").last ?? s
    }
    
    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 {
            let t = y
            y = x % y
            x = t
        }
        return abs(x)
    }
}
