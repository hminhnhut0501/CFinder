import Foundation
import OSLog

public final class VideoProbeService: Sendable {
    public static let shared = VideoProbeService()
    private let logger = Logger(subsystem: "com.sfinder.core", category: "VideoProbeService")
    
    private init() {}
    
    // MARK: - Public Probe API
    
    public func probe(fileURL: URL) async throws -> VideoProbeResult {
        let args = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            fileURL.path
        ]
        
        let jsonString = try await FFmpegManager.shared.runFFprobe(arguments: args)
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw FFmpegError.invalidOutput
        }
        
        let decoder = JSONDecoder()
        let probeRaw = try decoder.decode(FFprobeRawOutput.self, from: jsonData)
        
        let fileAttrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (fileAttrs?[.size] as? Int64) ?? Int64(probeRaw.format.size ?? "0") ?? 0
        let duration = Double(probeRaw.format.duration ?? "0") ?? 0.0
        let overallBitrate = Int64(probeRaw.format.bit_rate ?? "0") ?? (duration > 0 ? Int64(Double(fileSize * 8) / duration) : 0)
        let formatName = probeRaw.format.format_name ?? fileURL.pathExtension.lowercased()
        
        var videoStreams: [VideoStreamInfo] = []
        var audioStreams: [AudioStreamInfo] = []
        
        for rawStream in probeRaw.streams {
            if rawStream.codec_type == "video" {
                let vInfo = parseVideoStream(rawStream: rawStream, defaultDuration: duration, fileSize: fileSize)
                videoStreams.append(vInfo)
            } else if rawStream.codec_type == "audio" {
                let aInfo = parseAudioStream(rawStream: rawStream)
                audioStreams.append(aInfo)
            }
        }
        
        let isFastStart = checkFastStartMoovAtom(fileURL: fileURL)
        
        return VideoProbeResult(
            fileURL: fileURL,
            fileSize: fileSize,
            duration: duration,
            overallBitrate: overallBitrate,
            formatName: formatName,
            isFastStart: isFastStart,
            videoStream: videoStreams.first,
            audioStream: audioStreams.first,
            allVideoStreams: videoStreams,
            allAudioStreams: audioStreams
        )
    }
    
    // MARK: - Stream Parsing
    
    private func parseVideoStream(rawStream: FFprobeRawStream, defaultDuration: Double, fileSize: Int64) -> VideoStreamInfo {
        let codec = rawStream.codec_name ?? "unknown"
        let width = rawStream.width ?? 0
        let height = rawStream.height ?? 0
        let pixFmt = rawStream.pix_fmt ?? ""
        let colorSpace = rawStream.color_space
        let colorTransfer = rawStream.color_transfer
        let colorPrimaries = rawStream.color_primaries
        
        // Parse framerate (e.g. "30/1" or "293300/9777" or "60/1")
        var fps: Double = 30.0
        if let avgFps = rawStream.avg_frame_rate, avgFps.contains("/") {
            let parts = avgFps.split(separator: "/").compactMap { Double($0) }
            if parts.count == 2 && parts[1] > 0 {
                let computed = parts[0] / parts[1]
                if computed > 1 && computed < 240 {
                    fps = computed
                }
            }
        }
        
        // Check HDR
        let is10BitOrHigher = pixFmt.contains("10") || pixFmt.contains("12") || pixFmt.contains("16") || (rawStream.bits_per_raw_sample == "10")
        let hasHDRTransfer = ["smpte2084", "arib-std-b67", "linear"].contains(colorTransfer?.lowercased() ?? "")
        let hasHDRPrimaries = ["bt2020"].contains(colorPrimaries?.lowercased() ?? "")
        let isHDR = is10BitOrHigher || hasHDRTransfer || hasHDRPrimaries
        
        // Bitrate
        var bitRate = Int64(rawStream.bit_rate ?? "0") ?? 0
        if bitRate <= 0 && defaultDuration > 0 {
            // Rough estimation if stream bitrate is omitted
            bitRate = Int64(Double(fileSize * 8) / defaultDuration)
        }
        
        return VideoStreamInfo(
            index: rawStream.index,
            codecName: codec,
            profile: rawStream.profile,
            width: width,
            height: height,
            fps: fps,
            pixFmt: pixFmt,
            colorSpace: colorSpace,
            colorTransfer: colorTransfer,
            colorPrimaries: colorPrimaries,
            isHDR: isHDR,
            bitRate: bitRate
        )
    }
    
    private func parseAudioStream(rawStream: FFprobeRawStream) -> AudioStreamInfo {
        let codec = rawStream.codec_name ?? "unknown"
        let channels = rawStream.channels ?? 2
        let sampleRate = Int(rawStream.sample_rate ?? "44100") ?? 44100
        let bitRate = Int64(rawStream.bit_rate ?? "128000") ?? 128000
        
        return AudioStreamInfo(
            index: rawStream.index,
            codecName: codec,
            channels: channels,
            channelLayout: rawStream.channel_layout,
            sampleRate: sampleRate,
            bitRate: bitRate
        )
    }
    
    // MARK: - FastStart Moov Atom Inspector
    
    /// Reads MP4/MOV container box structure to verify if `moov` atom appears before `mdat`.
    /// This avoids running any external process and completes in < 0.1ms.
    public func checkFastStartMoovAtom(fileURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        guard ["mp4", "m4v", "mov"].contains(ext) else {
            return false // MKV, WebM, AVI, TS are not MP4 faststart containers
        }
        
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return false
        }
        defer { try? handle.close() }
        
        var currentOffset: UInt64 = 0
        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
            try handle.seek(toOffset: 0)
        } catch {
            return false
        }
        
        // Scan top-level boxes
        while currentOffset + 8 <= fileSize {
            do {
                try handle.seek(toOffset: currentOffset)
                let headerData = handle.readData(ofLength: 8)
                if headerData.count < 8 { break }
                
                let boxSize32 = headerData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let typeData = headerData.subdata(in: 4..<8)
                let boxType = String(data: typeData, encoding: .ascii) ?? ""
                
                var boxSize: UInt64 = UInt64(boxSize32)
                
                if boxSize32 == 1 {
                    // Extended 64-bit size
                    let extSizeData = handle.readData(ofLength: 8)
                    if extSizeData.count < 8 { break }
                    boxSize = extSizeData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                } else if boxSize32 == 0 {
                    // Box extends to end of file
                    boxSize = fileSize - currentOffset
                }
                
                if boxType == "moov" {
                    // Found moov before mdat! FastStart is true!
                    return true
                }
                
                if boxType == "mdat" {
                    // Found mdat before moov! FastStart is false!
                    return false
                }
                
                if boxSize <= 0 || boxSize > (fileSize - currentOffset) {
                    break
                }
                
                currentOffset += boxSize
            } catch {
                break
            }
        }
        
        return false
    }
}

// MARK: - Internal Decodable Structures for ffprobe JSON

private struct FFprobeRawOutput: Decodable {
    let streams: [FFprobeRawStream]
    let format: FFprobeRawFormat
}

private struct FFprobeRawFormat: Decodable {
    let format_name: String?
    let duration: String?
    let size: String?
    let bit_rate: String?
}

private struct FFprobeRawStream: Decodable {
    let index: Int
    let codec_name: String?
    let codec_type: String?
    let profile: String?
    let width: Int?
    let height: Int?
    let pix_fmt: String?
    let color_space: String?
    let color_transfer: String?
    let color_primaries: String?
    let bits_per_raw_sample: String?
    let avg_frame_rate: String?
    let r_frame_rate: String?
    let bit_rate: String?
    let channels: Int?
    let channel_layout: String?
    let sample_rate: String?
}
