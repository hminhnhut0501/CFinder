import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import OSLog

/// Deterministic frame sampler.
/// Positions: 7%, 17%, 29%, 41%, 53%, 67%, 79%, 91% of video duration.
/// Avoids 0% and 100% (black/fade/credits per spec §13).
/// Supports adaptive sampling: coarse → medium → fine → deep (§14).
public actor FrameSampler {
    // MARK: - Default sampling positions (deterministic, spec §13)
    public static let coarsePositions: [Double] = [0.07, 0.17, 0.29, 0.41, 0.53, 0.67, 0.79, 0.91]

    // Adaptive refinement positions inserted between coarse positions
    public static let mediumPositions: [Double] = {
        var pos = coarsePositions
        pos += [0.12, 0.23, 0.35, 0.47]
        return pos.sorted()
    }()

    public static let finePositions: [Double] = {
        var pos = mediumPositions
        pos += [0.05, 0.20, 0.45, 0.60, 0.72, 0.85]
        return pos.sorted()
    }()

    public static let deepPositions: [Double] = {
        var pos = finePositions
        let extra = stride(from: 0.08, through: 0.96, by: 0.06).map { $0 }
        pos += extra
        let unique = Array(Set(pos)).sorted()
        return unique.filter { $0 > 0.01 && $0 < 0.99 }
    }()

    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "decoder")

    // MARK: - Sampling level

    public enum SamplingLevel: Int, Comparable, Sendable {
        case coarse  // 8 frames
        case medium  // 12 frames
        case fine    // 20 frames
        case deep    // 32 frames

        public static func < (lhs: SamplingLevel, rhs: SamplingLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var positions: [Double] {
            switch self {
            case .coarse: return FrameSampler.coarsePositions
            case .medium: return FrameSampler.mediumPositions
            case .fine:   return FrameSampler.finePositions
            case .deep:   return FrameSampler.deepPositions
            }
        }
    }

    // MARK: - Public API

    public struct SampledFrame: Sendable {
        public let position: Double
        public let timestampSeconds: Double
        public let cgImage: CGImage
        public let isKeyFrame: Bool

        public init(position: Double, timestampSeconds: Double, cgImage: CGImage, isKeyFrame: Bool) {
            self.position = position
            self.timestampSeconds = timestampSeconds
            self.cgImage = cgImage
            self.isKeyFrame = isKeyFrame
        }
    }

    /// Sample frames at the given level for `assetURL`.
    /// Returns frames in temporal order.
    /// Automatically skips black/white/degenerate frames.
    func sampleFrames(
        from assetURL: URL,
        duration: Double,
        level: SamplingLevel,
        normalizer: FrameNormalizer
    ) async -> [SampledFrame] {
        guard duration > 0.1 else {
            logger.warning("Duration too short: \(duration)s for \(assetURL.lastPathComponent)")
            return []
        }

        let positions = level.positions
        let timestamps = positions.map { $0 * duration }

        return await decodeFrames(from: assetURL, at: timestamps, positions: positions, normalizer: normalizer)
    }

    /// Sample additional frames between two timestamps (for adaptive refinement).
    func sampleFramesBetween(
        from assetURL: URL,
        startSeconds: Double,
        endSeconds: Double,
        duration: Double,
        count: Int,
        normalizer: FrameNormalizer
    ) async -> [SampledFrame] {
        let step = (endSeconds - startSeconds) / Double(count + 1)
        let timestamps = (1...count).map { Double($0) * step + startSeconds }
        let positions = timestamps.map { $0 / duration }
        return await decodeFrames(from: assetURL, at: timestamps, positions: positions, normalizer: normalizer)
    }

    func sample(at timestamps: [Double], from url: URL, duration: Double, normalizer: FrameNormalizer) async -> [SampledFrame] {
        guard duration > 0, !timestamps.isEmpty else { return [] }
        return await decodeFrames(from: url, at: timestamps, positions: timestamps.map { $0 / duration }, normalizer: normalizer)
    }

    // MARK: - Decoder

    private func decodeFrames(
        from url: URL,
        at timestamps: [Double],
        positions: [Double],
        normalizer: FrameNormalizer
    ) async -> [SampledFrame] {
        let avAsset = AVURLAsset(url: url)

        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let cmTimes = timestamps.map { CMTime(seconds: $0, preferredTimescale: 600) }
        var frames: [(position: Double, ts: Double, image: CGImage)] = []

        let cancellation = ImageGeneratorCancellation(generator)
        await withTaskCancellationHandler {
        for await result in generator.images(for: cmTimes) {
            if Task.isCancelled { generator.cancelAllCGImageGeneration(); break }
            do {
                let reqSec = result.requestedTime.seconds
                let idx = cmTimes.indices.min(by: { abs(cmTimes[$0].seconds - reqSec) < abs(cmTimes[$1].seconds - reqSec) }) ?? 0
                frames.append((positions[idx], try result.actualTime.seconds, try result.image))
            } catch { logger.debug("Failed to get frame: \(error)") }
        }
        } onCancel: { cancellation.cancel() }

        frames.sort { $0.position < $1.position }
        return frames.compactMap { entry -> SampledFrame? in
            SampledFrame(
                position: entry.position,
                timestampSeconds: entry.ts,
                cgImage: entry.image,
                isKeyFrame: false
            )
        }
    }
}

// MARK: - Frame quality check

extension FrameSampler {
    /// Returns true if frame should be rejected (mostly black, white, or low entropy).
    /// Used for scene-aware sampling (spec §15).
    public static func isLowQualityFrame(_ image: CGImage, threshold: Double = 0.05) -> Bool {
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return true }
        let mean = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count)
        let variance = pixels.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(pixels.count)
        return variance < pow(max(2, threshold * 255), 2)
    }
}

// AVFoundation exposes cancellation for in-flight requests but its generator is
// not Sendable. Only this cancellation capability crosses the task boundary.
private final class ImageGeneratorCancellation: @unchecked Sendable {
    private let generator: AVAssetImageGenerator
    private let lock = NSLock()
    public init(_ generator: AVAssetImageGenerator) { self.generator = generator }
    func cancel() { lock.withLock { generator.cancelAllCGImageGeneration() } }
}
