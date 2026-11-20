import Foundation

/// Timestamp offset consensus with unique frame correspondences.
/// Equal scores prefer broader evidence, then the smaller absolute offset.
public actor TimelineAligner {
    let config: SimilarityConfiguration
    public init(config: SimilarityConfiguration = .default) { self.config = config }

    func align(framesA: [(timestamp: Double, dHash: UInt64)], framesB: [(timestamp: Double, dHash: UInt64)], durationA: Double, durationB: Double) -> AlignmentResult? {
        align(
            framesA: framesA.map { ($0.timestamp, $0.dHash, nil, nil) },
            framesB: framesB.map { ($0.timestamp, $0.dHash, nil, nil) },
            durationA: durationA,
            durationB: durationB
        )
    }

    func align(framesA: [(timestamp: Double, dHash: UInt64, centerDHash: UInt64?)], framesB: [(timestamp: Double, dHash: UInt64, centerDHash: UInt64?)], durationA: Double, durationB: Double) -> AlignmentResult? {
        align(
            framesA: framesA.map { ($0.timestamp, $0.dHash, $0.centerDHash, nil) },
            framesB: framesB.map { ($0.timestamp, $0.dHash, $0.centerDHash, nil) },
            durationA: durationA,
            durationB: durationB
        )
    }

    func align(framesA: [(timestamp: Double, dHash: UInt64, centerDHash: UInt64?, zoomDHash: UInt64?)], framesB: [(timestamp: Double, dHash: UInt64, centerDHash: UInt64?, zoomDHash: UInt64?)], durationA: Double, durationB: Double) -> AlignmentResult? {
        let minRequired = min(3, config.minimumAlignedSamples)
        let durRatio = min(durationA, durationB) / max(durationA, durationB)
        let isDurationSkewed = durRatio < Double(config.durationRatioMin)
        let effectiveMinRequired = isDurationSkewed ? 1 : minRequired
        guard framesA.count >= effectiveMinRequired, framesB.count >= effectiveMinRequired,
              durationA.isFinite, durationB.isFinite, durationA > 0, durationB > 0 else { return nil }
        let a = framesA.filter { $0.timestamp.isFinite }.sorted { $0.timestamp < $1.timestamp }
        let b = framesB.filter { $0.timestamp.isFinite }.sorted { $0.timestamp < $1.timestamp }
        let alignThreshold = max(0.76, config.nearDuplicateThreshold - 0.10)

        @inline(__always)
        func frameSim(_ left: (timestamp: Double, dHash: UInt64, centerDHash: UInt64?, zoomDHash: UInt64?), _ right: (timestamp: Double, dHash: UInt64, centerDHash: UInt64?, zoomDHash: UInt64?)) -> Float {
            var best = DHasher.similarity(left.dHash, right.dHash)
            if let ca = left.centerDHash, let cb = right.centerDHash {
                best = max(best, DHasher.similarity(ca, cb))
            }
            if let za = left.zoomDHash {
                best = max(best, DHasher.similarity(za, right.dHash))
                if let cb = right.centerDHash { best = max(best, DHasher.similarity(za, cb)) }
            }
            if let zb = right.zoomDHash {
                best = max(best, DHasher.similarity(left.dHash, zb))
                if let ca = left.centerDHash { best = max(best, DHasher.similarity(ca, zb)) }
            }
            return best
        }

        var offsets = Set<Double>([0])
        for left in a {
            for right in b where frameSim(left, right) >= alignThreshold {
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
                    frameSim(left, b[$0]) < frameSim(left, b[$1])
                }) else { continue }
                let similarity = frameSim(left, b[index])
                guard similarity >= alignThreshold else { continue }
                used.insert(index)
                scores.append(similarity)
                deltas.append(b[index].timestamp - left.timestamp)
            }
            guard scores.count >= effectiveMinRequired else { continue }
            let average = scores.reduce(0, +) / Float(scores.count)
            // When skewed (e.g. split parts), require higher confidence for small sample matches
            if isDurationSkewed && scores.count < minRequired {
                guard average >= 0.80 else { continue }
            }
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
