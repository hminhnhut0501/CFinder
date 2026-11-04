import Foundation
import CoreGraphics
import Accelerate

/// Difference Hash (dHash) — fast perceptual hash for visual similarity.
///
/// Algorithm:
///   1. Resize frame to 9×8 grayscale
///   2. For each row, compare adjacent pixels
///   3. Build 64-bit hash from 64 comparisons
///
/// Properties:
///   - O(1) comparison via Hamming distance
///   - Robust to mild brightness/contrast changes
///   - Sensitive to major visual changes
///   - Very fast (~microseconds per hash)
///
/// Version: v1
public struct DHasher: Sendable {
    public static let version = "v1"

    // MARK: - Hash computation

    /// Compute dHash for a normalized CGImage.
    /// Returns nil if image cannot be processed.
    public static func hash(_ image: CGImage) -> UInt64? {
        // Resize to 9×8 grayscale
        guard let gray = toGrayscale9x8(image) else { return nil }

        var hash: UInt64 = 0
        // gray is 9×8 = 72 pixels, row-major
        // For each row (8 rows), compare 8 adjacent pairs → 64 bits
        for row in 0..<8 {
            for col in 0..<8 {
                let left = gray[row * 9 + col]
                let right = gray[row * 9 + col + 1]
                let bit: UInt64 = left > right ? 1 : 0
                hash |= bit << UInt64(row * 8 + col)
            }
        }
        return hash
    }

    /// Hamming distance between two dHashes (0 = identical, 64 = completely different).
    public static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }

    /// Normalized similarity 0...1 (1 = identical).
    public static func similarity(_ a: UInt64, _ b: UInt64) -> Float {
        let dist = hammingDistance(a, b)
        return Float(64 - dist) / 64.0
    }

    // MARK: - Private helpers

    private static func toGrayscale9x8(_ image: CGImage) -> [UInt8]? {
        let targetW = 9
        let targetH = 8

        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: targetW,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: targetW * targetH)
        return Array(UnsafeBufferPointer(start: ptr, count: targetW * targetH))
    }
}
