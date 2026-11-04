import Foundation

/// Timestamp offset consensus with unique frame correspondences.
/// Equal scores prefer broader evidence, then the smaller absolute offset.
public actor TimelineAligner {
    let config: SimilarityConfiguration
    public init(config: SimilarityConfiguration = .default) { self.config = config }

    func align(framesA: [(timestamp: Double, dHash: UInt64)], framesB: [(timestamp: Double, dHash: UInt64)], durationA: Double, durationB: Double) -> AlignmentResult? {
        guard framesA.count >= config.minimumAlignedSamples, framesB.count >= config.minimumAlignedSamples,
              durationA.isFinite, durationB.isFinite, durationA > 0, durationB > 0 else { return nil }
        let a = framesA.filter { $0.timestamp.isFinite }.sorted { $0.timestamp < $1.timestamp }
        let b = framesB.filter { $0.timestamp.isFinite }.sorted { $0.timestamp < $1.timestamp }
        var offsets = Set<Double>([0])
        for left in a {
            for right in b where DHasher.similarity(left.dHash, right.dHash) >= config.nearDuplicateThreshold {
                offsets.insert(((right.timestamp - left.timestamp) * 10).rounded() / 10)
            }
        }
        var best: (offset: Double, count: Int, average: Float)?
        for offset in offsets.sorted() {
            var used = Set<Int>()
            var scores: [Float] = []
            var deltas: [Double] = []
            for left in a {
                let candidates = b.indices.filter { !used.contains($0) && abs(b[$0].timestamp - left.timestamp - offset) <= config.alignmentToleranceSeconds }
                guard let index = candidates.max(by: {
                    DHasher.similarity(left.dHash, b[$0].dHash) < DHasher.similarity(left.dHash, b[$1].dHash)
                }) else { continue }
                let similarity = DHasher.similarity(left.dHash, b[index].dHash)
                guard similarity >= config.nearDuplicateThreshold else { continue }
                used.insert(index)
                scores.append(similarity)
                deltas.append(b[index].timestamp - left.timestamp)
            }
            guard scores.count >= config.minimumAlignedSamples else { continue }
            let average = scores.reduce(0, +) / Float(scores.count)
            deltas.sort()
            let refined = deltas[deltas.count / 2]
            if best == nil || scores.count > best!.count ||
                (scores.count == best!.count && (average > best!.average + 0.0001 ||
                (abs(average - best!.average) <= 0.0001 && abs(refined) < abs(best!.offset)))) {
                best = (refined, scores.count, average)
            }
        }
        guard let best else { return nil }
        let overlap = max(0, min(durationA, durationB - best.offset) - max(0, -best.offset))
        guard overlap > 0 else { return nil }
        return AlignmentResult(offsetSeconds: best.offset, alignmentConfidence: best.average,
            matchedFrames: best.count, unmatchedFrames: max(0, min(a.count, b.count) - best.count),
            coverageA: Float(min(1, overlap / durationA)), coverageB: Float(min(1, overlap / durationB)))
    }
}
