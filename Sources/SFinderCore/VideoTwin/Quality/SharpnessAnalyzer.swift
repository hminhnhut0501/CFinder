import CoreGraphics
import Foundation

/// Normalized Laplacian variance, used only to compare frames of the same content.
public struct SharpnessAnalyzer {
    public static func score(_ image: CGImage) -> Float? {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size)); return true
        }
        guard drawn else { return nil }
        var values: [Double] = []
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let i = y * size + x
                values.append(Double(pixels[i - 1]) + Double(pixels[i + 1]) + Double(pixels[i - size]) + Double(pixels[i + size]) - 4 * Double(pixels[i]))
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return Float(min(1, log1p(variance) / log1p(4000)))
    }
}
