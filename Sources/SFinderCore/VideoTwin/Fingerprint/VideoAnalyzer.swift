import Foundation
import CoreGraphics

/// Each worker owns its decoder and normalizer. Only eight frames are decoded
/// initially; a promising partial candidate can request more in MatchEngine.
public struct VideoAnalyzer: Sendable {
    func analyze(_ input: VideoAsset) async -> VideoAsset {
        if Task.isCancelled {
            var asset = input
            asset.analysisState = .failed
            asset.errorState = .analysisFailed
            return asset
        }
        if input.analysisState == .qualityAnalyzed { return input }
        var asset = input
        asset.fingerprints = []
        let probe = NativeMetadataEngine()
        asset.metadata = await probe.probe(asset: asset)
        if Task.isCancelled { return asset }
        guard asset.metadata != nil else {
            asset.analysisState = .failed
            asset.errorState = .probeFailed
            return asset
        }
        do {
            let evidence = try await Self.fingerprintBatch(asset, level: .coarse)
            asset.fingerprints = evidence.samples
            asset.watermark = evidence.watermark
            asset.quality = await QualityAnalyzer().analyze(asset: asset)
            asset.analysisState = evidence.decodedCount == 0 ? .failed : .qualityAnalyzed
            asset.errorState = evidence.decodedCount == 0 ? .decodeFailed : (asset.fingerprints.count < SimilarityConfiguration.default.minimumAlignedSamples ? .insufficientVisualEvidence : nil)
        } catch is CancellationError {
            asset.analysisState = .failed
            asset.errorState = .analysisFailed
        } catch {
            asset.analysisState = .failed
            asset.errorState = .decodeFailed
        }
        return asset
    }

    public static func fingerprints(_ asset: VideoAsset, level: FrameSampler.SamplingLevel, times: [Double]? = nil) async throws -> [FrameSample] {
        try await fingerprintBatch(asset, level: level, times: times).samples
    }

    private static func fingerprintBatch(_ asset: VideoAsset, level: FrameSampler.SamplingLevel, times: [Double]? = nil) async throws -> (samples: [FrameSample], decodedCount: Int, watermark: WatermarkAssessment?) {
        let duration = asset.metadata?.durationSeconds ?? 0
        let sampler = FrameSampler(), normalizer = FrameNormalizer()
        let frames: [FrameSampler.SampledFrame]
        if let times { frames = await sampler.sample(at: times, from: asset.path, duration: duration, normalizer: normalizer) }
        else { frames = await sampler.sampleFrames(from: asset.path, duration: duration, level: level, normalizer: normalizer) }
        var samples: [FrameSample] = []
        var normImages: [CGImage] = []
        var frameTimes: [Double] = []
        for frame in frames {
            try Task.checkCancellation()
            let (sample, normImg): (FrameSample?, CGImage?) = autoreleasepool {
                let normalized = normalizer.normalize(frame.cgImage, isHDR: asset.metadata?.videoStream?.isHDR ?? false)
                let normImg = normalized.image
                guard !FrameSampler.isLowQualityFrame(normImg),
                      let d = DHasher.hash(normImg),
                      let p = PHasher.hash(normImg) else { return (nil, nil) }

                let (centerD, centerP, zoomD, zoomP, gridP) = Self.extractRegionalFingerprints(from: normImg)

                let s = FrameSample(
                    id: UUID(),
                    assetID: asset.id,
                    position: frame.position,
                    timestampSeconds: frame.timestampSeconds,
                    visualFingerprint: VisualFingerprint(
                        dHash: d,
                        pHash: p,
                        centerDHash: centerD,
                        centerPHash: centerP,
                        zoomDHash: zoomD,
                        zoomPHash: zoomP,
                        gridPHashes: gridP,
                        featurePrint: nil,
                        colorSignature: nil,
                        algorithmVersions: AlgorithmVersions()
                    ),
                    sharpness: SharpnessAnalyzer.score(normImg),
                    normalizationVersion: "v2"
                )
                return (s, normImg)
            }
            if let sample {
                samples.append(sample)
                if let normImg {
                    normImages.append(normImg)
                    frameTimes.append(frame.timestampSeconds)
                }
            }
        }
        let watermark = FastWatermarkDetector.detect(from: normImages, timestamps: frameTimes)
        return (samples, frames.count, watermark)
    }

    /// Computes center safe-region hashes, zoom/crop hashes (~1.4x-1.8x zoom or 9:16 vertical crop),
    /// and 2x2 grid pHashes (robust against partial text/overlay occlusion).
    private static func extractRegionalFingerprints(from image: CGImage) -> (centerD: UInt64?, centerP: [UInt8]?, zoomD: UInt64?, zoomP: [UInt8]?, gridP: [[UInt8]]?) {
        autoreleasepool {
            let w = CGFloat(image.width)
            let h = CGFloat(image.height)
            guard w >= 32, h >= 32 else { return (nil, nil, nil, nil, nil) }

            var centerD: UInt64?
            var centerP: [UInt8]?
            let centerRect = CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.64, height: h * 0.64).integral
            if centerRect.width >= 16, centerRect.height >= 16, let cropped = image.cropping(to: centerRect) {
                centerD = DHasher.hash(cropped)
                centerP = PHasher.hash(cropped)
            }

            // Deep Zoom & Vertical Crop Region (~1.4x-1.8x zoom, or 9:16 vertical slice from 16:9)
            var zoomD: UInt64?
            var zoomP: [UInt8]?
            let zoomRect = CGRect(x: w * 0.22, y: h * 0.22, width: w * 0.56, height: h * 0.56).integral
            if zoomRect.width >= 16, zoomRect.height >= 16, let zCropped = image.cropping(to: zoomRect) {
                zoomD = DHasher.hash(zCropped)
                zoomP = PHasher.hash(zCropped)
            }

            let halfW = floor(w * 0.5)
            let halfH = floor(h * 0.5)
            var grid: [[UInt8]] = []
            grid.reserveCapacity(4)
            let rects = [
                CGRect(x: 0, y: 0, width: halfW, height: halfH),
                CGRect(x: halfW, y: 0, width: w - halfW, height: halfH),
                CGRect(x: 0, y: halfH, width: halfW, height: h - halfH),
                CGRect(x: halfW, y: halfH, width: w - halfW, height: h - halfH)
            ]
            for rect in rects {
                if let qImg = image.cropping(to: rect), let qHash = PHasher.hash(qImg) {
                    grid.append(qHash)
                }
            }
            return (centerD, centerP, zoomD, zoomP, grid.count == 4 ? grid : nil)
        }
    }
}
