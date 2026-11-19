import Foundation
import CoreGraphics

/// Each worker owns its decoder and normalizer. Only eight frames are decoded
/// initially; a promising partial candidate can request more in MatchEngine.
public struct VideoAnalyzer: Sendable {
    func analyze(_ input: VideoAsset) async throws -> VideoAsset {
        try Task.checkCancellation()
        if input.analysisState == .qualityAnalyzed { return input }
        var asset = input
        asset.fingerprints = []
        let probe = NativeMetadataEngine()
        asset.metadata = await probe.probe(asset: asset)
        try Task.checkCancellation()
        guard asset.metadata != nil else {
            asset.analysisState = .failed; asset.errorState = .probeFailed
            return asset
        }
        let evidence = try await Self.fingerprintBatch(asset, level: .coarse)
        asset.fingerprints = evidence.samples
        asset.quality = await QualityAnalyzer().analyze(asset: asset)
        asset.analysisState = evidence.decodedCount == 0 ? .failed : .qualityAnalyzed
        asset.errorState = evidence.decodedCount == 0 ? .decodeFailed : (asset.fingerprints.count < SimilarityConfiguration.default.minimumAlignedSamples ? .insufficientVisualEvidence : nil)
        return asset
    }

    public static func fingerprints(_ asset: VideoAsset, level: FrameSampler.SamplingLevel, times: [Double]? = nil) async throws -> [FrameSample] {
        try await fingerprintBatch(asset, level: level, times: times).samples
    }

    private static func fingerprintBatch(_ asset: VideoAsset, level: FrameSampler.SamplingLevel, times: [Double]? = nil) async throws -> (samples: [FrameSample], decodedCount: Int) {
        let duration = asset.metadata?.durationSeconds ?? 0
        let sampler = FrameSampler(), normalizer = FrameNormalizer()
        let frames: [FrameSampler.SampledFrame]
        if let times { frames = await sampler.sample(at: times, from: asset.path, duration: duration, normalizer: normalizer) }
        else { frames = await sampler.sampleFrames(from: asset.path, duration: duration, level: level, normalizer: normalizer) }
        var samples: [FrameSample] = []
        for frame in frames {
            try Task.checkCancellation()
            guard !FrameSampler.isLowQualityFrame(frame.cgImage) else { continue }
            let normalized = await normalizer.normalize(frame.cgImage, isHDR: asset.metadata?.videoStream?.isHDR ?? false)
            let normImg = normalized.image
            guard !FrameSampler.isLowQualityFrame(normImg),
                  let d = DHasher.hash(normImg),
                  let p = PHasher.hash(normImg) else { continue }

            let (centerD, centerP, gridP) = Self.extractRegionalFingerprints(from: normImg)

            samples.append(FrameSample(
                id: UUID(),
                assetID: asset.id,
                position: frame.position,
                timestampSeconds: frame.timestampSeconds,
                visualFingerprint: VisualFingerprint(
                    dHash: d,
                    pHash: p,
                    centerDHash: centerD,
                    centerPHash: centerP,
                    gridPHashes: gridP,
                    featurePrint: nil,
                    colorSignature: nil,
                    algorithmVersions: AlgorithmVersions()
                ),
                sharpness: SharpnessAnalyzer.score(normImg),
                normalizationVersion: "v2"
            ))
        }
        return (samples, frames.count)
    }

    /// Computes center safe-region hashes (ignoring outer 18% margins where logos/captions live)
    /// and 2x2 grid pHashes (robust against partial text/overlay occlusion).
    private static func extractRegionalFingerprints(from image: CGImage) -> (UInt64?, [UInt8]?, [[UInt8]]?) {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        guard w >= 32, h >= 32 else { return (nil, nil, nil) }

        var centerD: UInt64?
        var centerP: [UInt8]?
        let centerRect = CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.64, height: h * 0.64).integral
        if centerRect.width >= 16, centerRect.height >= 16, let cropped = image.cropping(to: centerRect) {
            centerD = DHasher.hash(cropped)
            centerP = PHasher.hash(cropped)
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
        return (centerD, centerP, grid.count == 4 ? grid : nil)
    }
}
