import Foundation

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
            let image = await normalizer.normalize(frame.cgImage, isHDR: asset.metadata?.videoStream?.isHDR ?? false)
            guard !FrameSampler.isLowQualityFrame(image.image), let d = DHasher.hash(image.image), let p = PHasher.hash(image.image) else { continue }
            samples.append(FrameSample(id: UUID(), assetID: asset.id, position: frame.position, timestampSeconds: frame.timestampSeconds,
                visualFingerprint: VisualFingerprint(dHash: d, pHash: p, featurePrint: nil, colorSignature: nil, algorithmVersions: AlgorithmVersions()), sharpness: SharpnessAnalyzer.score(image.image), normalizationVersion: "v1"))
        }
        return (samples, frames.count)
    }
}
