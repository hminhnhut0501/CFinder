import Foundation
import AVFoundation
import CoreGraphics
import Vision

/// Relative overlay evidence only. OCR is not a standalone watermark classifier.
/// Logos without text and bottom-centre subtitles remain warning-only.
public actor WatermarkAnalyzer {
    struct TextBox: Sendable {
        let text: String
        let region: WatermarkRegion
        let confidence: Float
    }
    struct Frame: Sendable {
        let time: Double
        let pixels: [UInt8]
        let texts: [TextBox]
    }
    public static let width = 192
    public static let height = 108

    public init() {}

    public func analyze(_ a: VideoAsset, _ b: VideoAsset, match: MatchResult) async throws -> (WatermarkAssessment, WatermarkAssessment)? {
        guard match.matchType != .exact, match.coverageA >= 0.98, match.coverageB >= 0.98,
              let va = a.metadata?.videoStream, let vb = b.metadata?.videoStream,
              va.displayWidth > 0, va.displayHeight > 0, vb.displayWidth > 0, vb.displayHeight > 0,
              abs((Double(va.displayWidth) / Double(va.displayHeight)) / (Double(vb.displayWidth) / Double(vb.displayHeight)) - 1) < 0.01 else { return nil }
        let durationA = a.metadata?.durationSeconds ?? 0
        let durationB = b.metadata?.durationSeconds ?? 0
        let offset = match.alignment?.offsetSeconds ?? 0
        let start = max(0, -offset), end = min(durationA, durationB - offset)
        guard end > start, min(durationA, durationB) / max(durationA, durationB, 0.001) >= 0.98 else { return nil }
        let timesA = FrameSampler.coarsePositions.map { start + (end - start) * $0 }
        let decodedA = try await frames(a.path, times: timesA)
        let decodedB = try await frames(b.path, times: timesA.map { $0 + offset })
        let indices = decodedA.keys.filter { index in
            guard let frameA = decodedA[index], let frameB = decodedB[index] else { return false }
            return abs(frameA.time - frameB.time + offset) < 0.08
        }.sorted()
        let framesA = indices.compactMap { decodedA[$0] }, framesB = indices.compactMap { decodedB[$0] }
        try Task.checkCancellation()
        var resultA = Self.assess(framesA, against: framesB, peer: b.id, comparable: WatermarkPolicy.comparable(a, b))
        var resultB = Self.assess(framesB, against: framesA, peer: a.id, comparable: WatermarkPolicy.comparable(b, a))
        func attributedToPeer(_ suspect: WatermarkAssessment, _ marked: WatermarkAssessment) -> WatermarkAssessment {
            guard suspect.status == .possible, marked.status == .detected,
                  suspect.evidence.allSatisfy({ $0.text == nil }),
                  suspect.evidence.allSatisfy({ evidence in marked.evidence.contains { Self.overlap(evidence.region, $0.region) > 0.25 } }) else { return suspect }
            return WatermarkAssessment(status: .noEvidence, peerID: suspect.peerID, checkedFrames: suspect.checkedFrames, supportingFrames: 0, evidence: [], explanation: "The localized difference is attributed to added text in the compared copy. Other watermarks may still be present.", comparableAlternative: suspect.comparableAlternative)
        }
        resultA = attributedToPeer(resultA, resultB)
        resultB = attributedToPeer(resultB, resultA)
        return (resultA, resultB)
    }

    private func frames(_ url: URL, times: [Double]) async throws -> [Int: Frame] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let cancellation = WatermarkDecodeCancellation(generator)
        var frames: [Int: Frame] = [:]
        try await withTaskCancellationHandler {
            for await result in generator.images(for: times.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
                try Task.checkCancellation()
                guard let index = times.indices.min(by: { abs(times[$0] - result.requestedTime.seconds) < abs(times[$1] - result.requestedTime.seconds) }) else { continue }
                if let image = try? result.image, let time = try? result.actualTime.seconds {
                    frames[index] = try? Self.frame(image, time: time)
                }
            }
        } onCancel: { cancellation.cancel() }
        try Task.checkCancellation()
        return frames
    }

    static func frame(_ image: CGImage, time: Double) throws -> Frame {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CocoaError(.coderInvalidValue) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let texts = (request.results ?? []).compactMap { observation -> TextBox? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let rect = observation.boundingBox
            return TextBox(text: candidate.string, region: WatermarkRegion(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height), confidence: candidate.confidence)
        }
        return Frame(time: time, pixels: pixels, texts: texts)
    }

    static func assess(_ frames: [Frame], against peers: [Frame], peer: UUID, comparable: Bool) -> WatermarkAssessment {
        let count = min(frames.count, peers.count)
        guard count >= 6 else {
            return WatermarkAssessment(status: .unavailable, peerID: peer, checkedFrames: count, supportingFrames: 0, evidence: [], explanation: "Not enough aligned frames to assess overlays.", comparableAlternative: false)
        }
        var groups: [String: [WatermarkEvidence]] = [:]
        var candidates: [String: WatermarkRegion] = [:]
        var changes: [String: [Double]] = [:]
        for i in 0..<count {
            let a = frames[i], b = peers[i]
            guard a.pixels.count == width * height, b.pixels.count == width * height else { continue }
            for text in a.texts where text.confidence >= 0.75 && text.text.count >= 3 {
                let r = text.region
                guard r.width * r.height < 0.15, r.width > 0.02, r.height > 0.01 else { continue }
                let key = text.text.lowercased().filter { $0.isLetter || $0.isNumber }
                guard key.count >= 3 else { continue }
                // The same text in the peer is shared scene content or a shared overlay.
                guard !b.texts.contains(where: { $0.text.lowercased().filter { $0.isLetter || $0.isNumber } == key && overlap($0.region, r) > 0.25 }) else { continue }
                if let existing = candidates[key], abs(existing.x - r.x) + abs(existing.y - r.y) > 0.07 { continue }
                let local = difference(a.pixels, b.pixels, region: expanded(r))
                let global = difference(a.pixels, b.pixels, region: nil)
                guard local > 0.055, global < 0.065, local > global * 2 else { continue }
                candidates[key] = r
                if groups[key]?.last?.seconds != a.time {
                    groups[key, default: []].append(WatermarkEvidence(seconds: a.time, peerSeconds: b.time, region: r, text: text.text))
                    if i > 0 { changes[key, default: []].append(difference(b.pixels, peers[i - 1].pixels, region: expanded(r))) }
                }
            }
        }
        let best = groups.max { $0.value.count < $1.value.count }
        if let best, let region = candidates[best.key], best.value.count >= 3 {
            let bottomCentre = region.y > 0.65 && region.x < 0.8 && region.x + region.width > 0.2
            let changedBackground = (changes[best.key] ?? []).filter { $0 > 0.025 }.count >= 3
            let strong = best.value.count >= max(6, Int(ceil(Double(count) * 0.75))) && !bottomCentre && changedBackground
            return WatermarkAssessment(status: strong ? .detected : .possible, peerID: peer, checkedFrames: count, supportingFrames: best.value.count, evidence: Array(best.value.prefix(3)), explanation: strong ? "Repeated text overlay is present in this copy but absent from aligned peer frames across changing backgrounds." : "Repeated extra text may be an overlay, subtitle or scene detail. Review before applying a quality penalty.", comparableAlternative: comparable)
        }
        // Non-text corner patches are deliberately warning-only: a static object can resemble a logo.
        let corners = [WatermarkRegion(x: 0, y: 0, width: 0.22, height: 0.2), WatermarkRegion(x: 0.78, y: 0, width: 0.22, height: 0.2), WatermarkRegion(x: 0, y: 0.8, width: 0.22, height: 0.2), WatermarkRegion(x: 0.78, y: 0.8, width: 0.22, height: 0.2)]
        for region in corners {
            let hits = (0..<count).filter {
                difference(frames[$0].pixels, peers[$0].pixels, region: region) > 0.045 && difference(frames[$0].pixels, peers[$0].pixels, region: nil) < 0.025
            }
            if hits.count >= 6 {
                let evidence = hits.prefix(3).map { WatermarkEvidence(seconds: frames[$0].time, peerSeconds: peers[$0].time, region: region, text: nil) }
                return WatermarkAssessment(status: .possible, peerID: peer, checkedFrames: count, supportingFrames: hits.count, evidence: evidence, explanation: "A persistent corner difference may be a logo or overlay. It is not automatically penalized.", comparableAlternative: comparable)
            }
        }
        return WatermarkAssessment(status: .noEvidence, peerID: peer, checkedFrames: count, supportingFrames: 0, evidence: [], explanation: "No repeated extra overlay was identified in sampled frames. This does not prove the video has no watermark.", comparableAlternative: comparable)
    }

    private static func expanded(_ r: WatermarkRegion) -> WatermarkRegion {
        let x = max(0, r.x - 0.015), y = max(0, r.y - 0.015)
        return WatermarkRegion(x: x, y: y, width: min(1 - x, r.width + 0.03), height: min(1 - y, r.height + 0.03))
    }
    private static func overlap(_ a: WatermarkRegion, _ b: WatermarkRegion) -> Double {
        let w = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
        let h = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
        return w * h / max(0.00001, min(a.width * a.height, b.width * b.height))
    }
    public static func difference(_ a: [UInt8], _ b: [UInt8], region: WatermarkRegion?) -> Double {
        guard a.count == width * height, b.count == a.count else { return 1 }
        let r = region ?? WatermarkRegion(x: 0, y: 0, width: 1, height: 1)
        let left = max(0, min(width - 1, Int(r.x * Double(width))))
        let top = max(0, min(height - 1, Int(r.y * Double(height))))
        let right = max(left + 1, min(width, Int((r.x + r.width) * Double(width))))
        let bottom = max(top + 1, min(height, Int((r.y + r.height) * Double(height))))
        var total = 0.0, count = 0
        for y in top..<bottom { for x in left..<right {
            total += Double(abs(Int(a[y * width + x]) - Int(b[y * width + x]))) / 255
            count += 1
        } }
        return total / Double(max(1, count))
    }
}

private final class WatermarkDecodeCancellation: @unchecked Sendable {
    private let generator: AVAssetImageGenerator
    private let lock = NSLock()
    public init(_ generator: AVAssetImageGenerator) { self.generator = generator }
    func cancel() { lock.withLock { generator.cancelAllCGImageGeneration() } }
}
