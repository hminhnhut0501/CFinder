import Foundation
import CoreGraphics
import Accelerate

/// Perceptual Hash (pHash) via DCT — more robust than dHash.
///
/// Algorithm:
///   1. Resize frame to 32×32 grayscale
///   2. Apply 2D DCT
///   3. Take top-left 8×8 = 64 low-frequency coefficients (skip [0,0] DC)
///   4. Compute median of those 64 values
///   5. Build 64-bit hash: 1 if coefficient > median, else 0
///
/// Properties:
///   - Robust to JPEG/codec compression, brightness, contrast changes
///   - Resistant to minor scaling
///   - Slower than dHash but more accurate
///   - Hamming distance comparison
///
/// Version: v1
public struct PHasher: Sendable {
    public static let version = "v1"

    // DCT input size
    public static let dctSize = 32
    // Hash coefficient region (top-left of DCT, skip DC)
    public static let hashSize = 8

    // MARK: - Hash computation

    /// Returns 64-byte pHash (one bit per byte for easy storage/comparison).
    public static func hash(_ image: CGImage) -> [UInt8]? {
        // Step 1: 32×32 grayscale
        guard let pixels = toGrayscale32x32(image) else { return nil }

        // Step 2: 2D DCT via separable 1D DCTs
        let dct = computeDCT2D(pixels: pixels, n: dctSize)

        // Step 3: Extract 8×8 low-frequency block (skip [0,0])
        var coefficients = [Float]()
        coefficients.reserveCapacity(hashSize * hashSize)
        for row in 0..<hashSize {
            for col in 0..<hashSize {
                if row == 0 && col == 0 { continue }  // skip DC
                coefficients.append(dct[row * dctSize + col])
            }
        }
        // Fill to 64 if we skipped DC
        let dcVal = dct[0]
        coefficients.insert(dcVal < 0 ? 0 : dcVal, at: 0)  // placeholder for bit 0

        // Step 4: Median
        let sorted = coefficients.sorted()
        let median = sorted[sorted.count / 2]

        // Step 5: Hash bits
        var hashBytes = [UInt8](repeating: 0, count: coefficients.count)
        for (i, coeff) in coefficients.enumerated() {
            hashBytes[i] = coeff > median ? 1 : 0
        }

        return hashBytes
    }

    /// Hamming distance between two pHash byte arrays.
    public static func hammingDistance(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return a.count * 8 }
        return zip(a, b).reduce(0) { $0 + ($1.0 != $1.1 ? 1 : 0) }
    }

    /// Normalized similarity 0...1
    public static func similarity(_ a: [UInt8], _ b: [UInt8]) -> Float {
        guard !a.isEmpty else { return 0 }
        let dist = hammingDistance(a, b)
        return Float(a.count - dist) / Float(a.count)
    }

    // MARK: - Private: Image → grayscale pixels

    private static func toGrayscale32x32(_ image: CGImage) -> [Float]? {
        let n = dctSize
        guard let ctx = CGContext(
            data: nil,
            width: n,
            height: n,
            bitsPerComponent: 8,
            bytesPerRow: n,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))

        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: n * n)
        return (0..<n*n).map { Float(ptr[$0]) }
    }

    // MARK: - Private: 2D DCT via row/column separable 1D DCTs

    private static func computeDCT2D(pixels: [Float], n: Int) -> [Float] {
        var result = pixels

        // Apply 1D DCT to each row
        for row in 0..<n {
            let rowSlice = Array(pixels[(row*n)..<(row*n+n)])
            let rowDCT = dct1D(rowSlice)
            for col in 0..<n {
                result[row * n + col] = rowDCT[col]
            }
        }

        // Apply 1D DCT to each column
        for col in 0..<n {
            var colData = [Float](repeating: 0, count: n)
            for row in 0..<n { colData[row] = result[row * n + col] }
            let colDCT = dct1D(colData)
            for row in 0..<n { result[row * n + col] = colDCT[row] }
        }

        return result
    }

    /// Type-II DCT (normalized)
    private static func dct1D(_ input: [Float]) -> [Float] {
        let n = input.count
        var output = [Float](repeating: 0, count: n)

        // Use vDSP for fast DCT if available, otherwise naive
        // vDSP DCT-II:
        let setup = vDSP.DCT(count: n, transformType: .II)
        if let s = setup {
            output = s.transform(input)
        } else {
            // Naive O(n²) fallback
            for k in 0..<n {
                var sum: Float = 0
                for i in 0..<n {
                    sum += input[i] * cos(.pi * Float(k) * (2 * Float(i) + 1) / (2 * Float(n)))
                }
                output[k] = sum
            }
        }
        return output
    }
}
