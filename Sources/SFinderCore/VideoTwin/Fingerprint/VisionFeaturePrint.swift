import Foundation
import Vision
import CoreImage
import OSLog

/// Wraps Apple's Vision FeaturePrint for high-quality visual similarity.
///
/// VNGenerateImageFeaturePrintRequest produces a feature embedding vector
/// that captures semantic visual content. More robust than dHash/pHash
/// for re-encoded, color-shifted, slightly cropped content.
///
/// Cost: Higher than dHash/pHash. Should be used:
///   - After dHash/pHash have narrowed candidates
///   - In the "fine" verification stage
///   - Can be precomputed in background for promising candidates
///
/// Version: v1
public actor VisionFeaturePrint {
    public static let version = "v1"

    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "fingerprint")

    // MARK: - Public API

    /// Compute Vision FeaturePrint for a normalized CGImage.
    /// Returns Float array (embedding vector) or nil on failure.
    func computeFeaturePrint(for image: CGImage) async -> [Float]? {
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                guard let result = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(returning: nil)
                    return
                }
                // Extract float data from the feature print
                let floats = self.extractFloats(from: result)
                continuation.resume(returning: floats)
            }

            // Use .accurate for better results (slower)
            request.imageCropAndScaleOption = .centerCrop

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                self.logger.warning("FeaturePrint request failed: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    /// Compute cosine distance between two feature print observations.
    /// Returns 0...1 (0 = identical, 1 = completely different).
    func distance(
        _ observationA: VNFeaturePrintObservation,
        _ observationB: VNFeaturePrintObservation
    ) -> Float {
        var distance: Float = 0
        do {
            try observationA.computeDistance(&distance, to: observationB)
        } catch {
            logger.warning("FeaturePrint distance computation failed: \(error)")
            distance = 1.0
        }
        return distance
    }

    /// Compute similarity from two raw float embeddings using cosine similarity.
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return max(0, min(1, dot / denom))
    }

    // MARK: - Private

    private func extractFloats(from observation: VNFeaturePrintObservation) -> [Float]? {
        let data = observation.data
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0 else { return nil }

        var floats = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { ptr in
            if let baseAddr = ptr.baseAddress {
                let floatPtr = baseAddr.bindMemory(to: Float.self, capacity: count)
                for i in 0..<count {
                    floats[i] = floatPtr[i]
                }
            }
        }
        return floats
    }
}
