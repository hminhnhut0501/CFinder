import Foundation
import OSLog

public struct VideoNormalizerResult: Sendable {
    public let sourceURL: URL
    public let destinationURL: URL
    public let plan: NormalizationPlan
    public let verification: VideoVerificationReport
    public let elapsedTime: TimeInterval
    
    public var wasAlreadyOptimal: Bool {
        plan.strategy == .alreadyOptimal
    }
}

public final class VideoNormalizerEngine: Sendable {
    public static let shared = VideoNormalizerEngine()
    private let logger = Logger(subsystem: "com.sfinder.core", category: "VideoNormalizerEngine")
    
    private init() {}
    
    // MARK: - Smart Decision Engine
    
    public func analyze(fileURL: URL) async throws -> NormalizationPlan {
        let probeResult = try await VideoProbeService.shared.probe(fileURL: fileURL)
        
        guard let video = probeResult.videoStream else {
            throw VideoVerificationError.missingVideoStream
        }
        
        let isExtMP4 = ["mp4", "m4v"].contains(fileURL.pathExtension.lowercased())
        let isVideoH264 = video.isCompliantH264
        let isAudioCompliant = probeResult.audioStream == nil || (probeResult.audioStream?.isCompliantAAC ?? false)
        let isDimensionsReasonable = max(video.width, video.height) <= 1920
        let isBitrateReasonable = video.bitRate <= 5_500_000 // <= 5.5 Mbps
        
        // 1. Check if already 100% optimal for streaming
        if isExtMP4 && probeResult.isFastStart && isVideoH264 && isAudioCompliant && isDimensionsReasonable && isBitrateReasonable {
            return NormalizationPlan(
                strategy: .alreadyOptimal,
                sourceInfo: probeResult,
                targetWidth: video.width,
                targetHeight: video.height,
                targetVideoBitrate: video.bitRate,
                targetAudioBitrate: probeResult.audioStream?.bitRate ?? 128_000,
                needsToneMapping: false,
                needsAudioDownmix: false,
                encoder: "copy",
                summary: "Video đã đạt chuẩn streaming tối ưu (H.264 + AAC + FastStart). Không cần xử lý lại."
            )
        }
        
        // 2. Check if Fast Remux is possible (Stream Copy)
        // If streams are already H.264 + AAC stereo + within bitrate/resolution limits, but container is MKV/MOV or moov is at end
        if isVideoH264 && isAudioCompliant && isDimensionsReasonable && isBitrateReasonable {
            return NormalizationPlan(
                strategy: .remuxFastStart,
                sourceInfo: probeResult,
                targetWidth: video.width,
                targetHeight: video.height,
                targetVideoBitrate: video.bitRate,
                targetAudioBitrate: probeResult.audioStream?.bitRate ?? 128_000,
                needsToneMapping: false,
                needsAudioDownmix: false,
                encoder: "copy",
                summary: "Tái đóng gói siêu tốc (Fast Remux) sang MP4 FastStart (Giữ nguyên 100% chất lượng trong ~1s)."
            )
        }
        
        // 3. Otherwise: Transcode is required
        let (targetW, targetH) = calculateTargetResolution(width: video.width, height: video.height)
        let targetVBitrate = calculateTargetBitrate(width: targetW, height: targetH, fps: video.fps, sourceBitrate: video.bitRate)
        let needsDownmix = (probeResult.audioStream?.channels ?? 0) > 2 || !(probeResult.audioStream?.isCompliantAAC ?? true)
        let targetABitrate: Int64 = needsDownmix ? 160_000 : (probeResult.audioStream?.bitRate ?? 128_000)
        let needsToneMapping = video.isHDR
        
        let encoder = FFmpegManager.shared.hasVideoToolboxH264 ? "h264_videotoolbox" : "libx264"
        let speedDesc = encoder == "h264_videotoolbox" ? "Tăng tốc phần cứng Apple Silicon (VideoToolbox)" : "Mã hoá tối ưu CPU (libx264)"
        
        let summary = "Chuẩn hoá chất lượng cao: \(targetW)x\(targetH) @ \(String(format: "%.1f", Double(targetVBitrate) / 1_000_000.0)) Mbps (\(speedDesc))."
        
        return NormalizationPlan(
            strategy: .transcode,
            sourceInfo: probeResult,
            targetWidth: targetW,
            targetHeight: targetH,
            targetVideoBitrate: targetVBitrate,
            targetAudioBitrate: targetABitrate,
            needsToneMapping: needsToneMapping,
            needsAudioDownmix: needsDownmix,
            encoder: encoder,
            summary: summary
        )
    }
    
    // MARK: - Normalization Pipeline
    
    public func normalize(
        fileURL: URL,
        outputDirectory: URL? = nil,
        onProgress: (@Sendable (FFmpegProgress) -> Void)? = nil
    ) async throws -> VideoNormalizerResult {
        let startTime = Date()
        let plan = try await analyze(fileURL: fileURL)
        
        let targetDir = outputDirectory ?? fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let finalOutputURL = makeUniqueURL(directory: targetDir, baseName: "\(baseName)_stream", ext: "mp4")
        
        // Temporary atomic file
        let tempFileName = ".\(baseName).sfinder_transcoding_\(UUID().uuidString.prefix(8)).mp4"
        let tempOutputURL = targetDir.appendingPathComponent(tempFileName)
        
        defer {
            // Clean up temporary file if it still exists (e.g. on error or cancellation)
            if FileManager.default.fileExists(atPath: tempOutputURL.path) {
                try? FileManager.default.removeItem(at: tempOutputURL)
            }
        }
        
        // Build arguments
        var args = ["-y", "-progress", "pipe:1", "-i", fileURL.path]
        
        switch plan.strategy {
        case .alreadyOptimal, .remuxFastStart:
            args.append(contentsOf: [
                "-c:v", "copy",
                "-c:a", "copy",
                "-movflags", "+faststart",
                tempOutputURL.path
            ])
            
        case .transcode:
            // Video Filter: Resolution Clamp & ensure dimensions divisible by 2
            var filterParts: [String] = []
            
            // Tone mapping for HDR if needed
            if plan.needsToneMapping {
                filterParts.append("tonemap=reinhard:desat=0.5")
            }
            
            // Scale keeping aspect ratio inside targetWidth x targetHeight box, ensure even dimensions
            let scaleFilter = "scale='min(\(plan.targetWidth),iw)':-2:flags=bicubic,scale=trunc(iw/2)*2:trunc(ih/2)*2"
            filterParts.append(scaleFilter)
            filterParts.append("format=yuv420p")
            
            args.append(contentsOf: ["-vf", filterParts.joined(separator: ",")])
            
            // Video Encoder configuration
            if plan.encoder == "h264_videotoolbox" {
                args.append(contentsOf: [
                    "-c:v", "h264_videotoolbox",
                    "-b:v", "\(plan.targetVideoBitrate)",
                    "-maxrate", "\(Int64(Double(plan.targetVideoBitrate) * 1.35))",
                    "-bufsize", "\(plan.targetVideoBitrate * 2)",
                    "-profile:v", "high",
                    "-pix_fmt", "yuv420p"
                ])
            } else {
                args.append(contentsOf: [
                    "-c:v", "libx264",
                    "-crf", "22",
                    "-preset", "medium",
                    "-maxrate", "\(Int64(Double(plan.targetVideoBitrate) * 1.35))",
                    "-bufsize", "\(plan.targetVideoBitrate * 2)",
                    "-profile:v", "high",
                    "-pix_fmt", "yuv420p"
                ])
            }
            
            // Audio Encoder configuration
            if plan.needsAudioDownmix {
                args.append(contentsOf: [
                    "-c:a", "aac",
                    "-b:a", "\(plan.targetAudioBitrate)",
                    "-ac", "2",
                    "-ar", "48000"
                ])
            } else {
                // Audio is already compliant AAC stereo
                args.append(contentsOf: ["-c:a", "copy"])
            }
            
            // Streaming faststart
            args.append(contentsOf: [
                "-movflags", "+faststart",
                tempOutputURL.path
            ])
        }
        
        logger.info("Executing normalization with strategy \(String(describing: plan.strategy)): \(args.joined(separator: " "))")
        
        // Execute with progress
        _ = try await FFmpegManager.shared.runFFmpeg(
            arguments: args,
            totalDurationSeconds: plan.sourceInfo.duration,
            onProgress: onProgress
        )
        
        // Verify output integrity
        let verification = try await VideoVerificationService.shared.verify(outputURL: tempOutputURL, sourceInfo: plan.sourceInfo)
        
        if !verification.isValid {
            let errorMsg = verification.errors.joined(separator: "; ")
            throw VideoVerificationError.decodeError("Xác thực video đầu ra không đạt: \(errorMsg)")
        }
        
        // Move temporary file to final target atomically
        try FileManager.default.moveItem(at: tempOutputURL, to: finalOutputURL)
        
        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("Normalization completed in \(String(format: "%.2f", elapsed))s -> \(finalOutputURL.lastPathComponent)")
        
        return VideoNormalizerResult(
            sourceURL: fileURL,
            destinationURL: finalOutputURL,
            plan: plan,
            verification: verification,
            elapsedTime: elapsed
        )
    }
    
    // MARK: - Dimension & Bitrate Calculations
    
    private func calculateTargetResolution(width: Int, height: Int) -> (Int, Int) {
        guard width > 0 && height > 0 else { return (1920, 1080) }
        
        let isPortrait = height > width
        let maxAllowedLongEdge = 1920
        let maxAllowedShortEdge = 1080
        
        let longEdge = max(width, height)
        let shortEdge = min(width, height)
        
        var targetW = width
        var targetH = height
        
        if longEdge > maxAllowedLongEdge || shortEdge > maxAllowedShortEdge {
            let ratio = Double(width) / Double(height)
            if isPortrait {
                targetH = min(height, maxAllowedLongEdge)
                targetW = Int(Double(targetH) * ratio)
            } else {
                targetW = min(width, maxAllowedLongEdge)
                targetH = Int(Double(targetW) / ratio)
            }
        }
        
        // Ensure even dimensions
        targetW = targetW - (targetW % 2)
        targetH = targetH - (targetH % 2)
        
        return (targetW, targetH)
    }
    
    private func calculateTargetBitrate(width: Int, height: Int, fps: Double, sourceBitrate: Int64) -> Int64 {
        let pixels = width * height
        let frameRateMultiplier = fps > 45 ? 1.3 : 1.0
        
        let baseBitrate: Double
        if pixels >= 1920 * 1080 {
            // ~1080p
            baseBitrate = 3_800_000 * frameRateMultiplier
        } else if pixels >= 1280 * 720 {
            // ~720p
            baseBitrate = 2_000_000 * frameRateMultiplier
        } else if pixels >= 854 * 480 {
            // ~480p
            baseBitrate = 1_100_000 * frameRateMultiplier
        } else {
            // <= 360p
            baseBitrate = 750_000 * frameRateMultiplier
        }
        
        let target = Int64(baseBitrate)
        // If source bitrate is already lower than target, don't inflate!
        if sourceBitrate > 500_000 && sourceBitrate < target {
            return Int64(Double(sourceBitrate) * 0.95)
        }
        return target
    }
    
    private func makeUniqueURL(directory: URL, baseName: String, ext: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
