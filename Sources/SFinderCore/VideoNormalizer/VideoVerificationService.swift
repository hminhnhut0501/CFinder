import Foundation
import OSLog

public struct VideoVerificationReport: Sendable {
    public let isValid: Bool
    public let sourceSize: Int64
    public let outputSize: Int64
    public let savedBytes: Int64
    public let compressionRatio: Double // e.g. 0.35 means 35% of original size (saved 65%)
    public let outputDuration: Double
    public let isFastStart: Bool
    public let errors: [String]
    
    public var savedPercentage: Double {
        return (1.0 - compressionRatio) * 100.0
    }
}

public enum VideoVerificationError: LocalizedError, Sendable {
    case fileMissingOrEmpty
    case probeFailed(String)
    case durationMismatch(source: Double, output: Double)
    case missingVideoStream
    case missingAudioStream
    case nonCompliantVideoCodec(String)
    case nonCompliantPixelFormat(String)
    case moovAtomNotAtStart
    case decodeError(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileMissingOrEmpty:
            return "File xuất ra không tồn tại hoặc có dung lượng rỗng (0 bytes)."
        case .probeFailed(let msg):
            return "Không thể phân tích dữ liệu video đầu ra: \(msg)"
        case .durationMismatch(let src, let out):
            return "Thời lượng video đầu ra không khớp với file gốc (Gốc: \(String(format: "%.1f", src))s, Xuất: \(String(format: "%.1f", out))s)."
        case .missingVideoStream:
            return "File xuất ra không chứa luồng hình ảnh (Video stream)."
        case .missingAudioStream:
            return "File xuất ra bị mất luồng âm thanh trong khi video gốc có âm thanh."
        case .nonCompliantVideoCodec(let c):
            return "Codec video không đạt chuẩn H.264 (Phát hiện: \(c))."
        case .nonCompliantPixelFormat(let p):
            return "Định dạng màu không đạt chuẩn yuv420p (Phát hiện: \(p))."
        case .moovAtomNotAtStart:
            return "Cấu trúc container không tối ưu cho streaming (Moov atom không nằm ở đầu file)."
        case .decodeError(let err):
            return "Kiểm tra giải mã khung hình thất bại: \(err)"
        }
    }
}

public final class VideoVerificationService: Sendable {
    public static let shared = VideoVerificationService()
    private let logger = Logger(subsystem: "com.sfinder.core", category: "VideoVerificationService")
    
    private init() {}
    
    public func verify(outputURL: URL, sourceInfo: VideoProbeResult) async throws -> VideoVerificationReport {
        var errors: [String] = []
        
        // 1. File existence & size check
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
              let size = attrs[.size] as? Int64, size > 10 * 1024 else {
            throw VideoVerificationError.fileMissingOrEmpty
        }
        
        // 2. Probe output
        let outputProbe: VideoProbeResult
        do {
            outputProbe = try await VideoProbeService.shared.probe(fileURL: outputURL)
        } catch {
            throw VideoVerificationError.probeFailed(error.localizedDescription)
        }
        
        // 3. Duration check (allow 1.0s or 2% tolerance)
        if sourceInfo.duration > 2.0 {
            let diff = abs(outputProbe.duration - sourceInfo.duration)
            let tolerance = max(1.0, sourceInfo.duration * 0.02)
            if diff > tolerance {
                errors.append("Thời lượng lệch quá mức cho phép: \(String(format: "%.2f", diff))s")
            }
        }
        
        // 4. Video stream verification
        guard let outVideo = outputProbe.videoStream else {
            throw VideoVerificationError.missingVideoStream
        }
        
        if outVideo.codecName.lowercased() != "h264" {
            errors.append("Codec video không phải H.264 (nhận diện: \(outVideo.codecName))")
        }
        if outVideo.pixFmt.lowercased() != "yuv420p" {
            errors.append("Pixel format không phải yuv420p (nhận diện: \(outVideo.pixFmt))")
        }
        
        // 5. Audio stream verification
        if sourceInfo.hasAudio {
            guard let outAudio = outputProbe.audioStream else {
                throw VideoVerificationError.missingAudioStream
            }
            if outAudio.codecName.lowercased() != "aac" {
                errors.append("Codec âm thanh không phải AAC (nhận diện: \(outAudio.codecName))")
            }
            if outAudio.channels > 2 {
                errors.append("Số kênh âm thanh chưa được chuyển về Stereo (\(outAudio.channels) channels)")
            }
        }
        
        // 6. FastStart check
        if !outputProbe.isFastStart {
            errors.append("Moov atom chưa được đưa lên đầu file (chưa sẵn sàng phát stream)")
        }
        
        // 7. Spot-check decode integrity at 50% duration
        if outputProbe.duration > 1.0 {
            let checkTime = String(format: "%.2f", outputProbe.duration * 0.5)
            let spotCheckArgs = [
                "-v", "error",
                "-ss", checkTime,
                "-i", outputURL.path,
                "-vframes", "1",
                "-f", "null",
                "-"
            ]
            
            do {
                _ = try await FFmpegManager.shared.runFFmpeg(arguments: spotCheckArgs)
            } catch {
                errors.append("Lỗi giải mã mẫu khung hình tại giây \(checkTime): \(error.localizedDescription)")
            }
        }
        
        let ratio = sourceInfo.fileSize > 0 ? Double(size) / Double(sourceInfo.fileSize) : 1.0
        let savedBytes = max(0, sourceInfo.fileSize - size)
        
        let report = VideoVerificationReport(
            isValid: errors.isEmpty,
            sourceSize: sourceInfo.fileSize,
            outputSize: size,
            savedBytes: savedBytes,
            compressionRatio: ratio,
            outputDuration: outputProbe.duration,
            isFastStart: outputProbe.isFastStart,
            errors: errors
        )
        
        if !report.isValid {
            logger.warning("Verification failed for \(outputURL.lastPathComponent): \(errors.joined(separator: ", "))")
        } else {
            logger.info("Verification passed for \(outputURL.lastPathComponent). Saved: \(savedBytes / 1024 / 1024) MB (\(String(format: "%.1f", report.savedPercentage))%)")
        }
        
        return report
    }
}
