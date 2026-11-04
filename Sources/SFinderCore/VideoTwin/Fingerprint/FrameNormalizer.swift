import Foundation
import CoreImage
import CoreGraphics
import Accelerate
import OSLog

/// Normalizes a decoded CGImage before fingerprinting.
///
/// Pipeline (spec §17-18):
///   decoded frame
///     → rotation normalization
///     → black-bar detection & safe crop
///     → color normalization
///     → HDR normalization (tone map if needed)
///     → resize to target width (preserving aspect ratio)
///     → luminance normalization
public actor FrameNormalizer {
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "fingerprint")

    // MARK: - Configuration
    public struct Config: Sendable {
        public var targetWidth: Int = 256
        /// Minimum black-bar height as fraction of image height to crop
        public var blackBarThreshold: Double = 0.05
        /// Maximum fraction of image to crop as black bar (safety)
        public var maxCropFraction: Double = 0.30

        public init(targetWidth: Int = 256, blackBarThreshold: Double = 0.05, maxCropFraction: Double = 0.30) {
            self.targetWidth = targetWidth
            self.blackBarThreshold = blackBarThreshold
            self.maxCropFraction = maxCropFraction
        }
    }

    public let config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public API

    struct NormalizedFrame: Sendable {
        /// Normalized CGImage ready for fingerprinting
        let image: CGImage
        /// Applied crop rect (in original image coordinates)
        let cropRect: CGRect?
        let wasRotated: Bool
        let wasHDRToneMapped: Bool
    }

    func normalize(_ cgImage: CGImage, rotation: Double = 0, isHDR: Bool = false) -> NormalizedFrame {
        var image = cgImage
        var wasRotated = false
        var cropRect: CGRect? = nil
        var wasHDRToneMapped = false

        // 1. Rotation normalization (avoid duplicate rotation from AVFoundation)
        //    AVAssetImageGenerator applies preferredTransform, so usually rotation = 0 here.
        //    Handle residual rotation if needed.
        let rot = rotation.truncatingRemainder(dividingBy: 360)
        if abs(rot) > 1.0 {
            if let rotated = applyRotation(image, degrees: rot) {
                image = rotated
                wasRotated = true
            }
        }

        // 2. Black-bar detection and safe crop
        let detected = detectBlackBars(image)
        if let cropR = detected {
            if let cropped = cropImage(image, to: cropR) {
                image = cropped
                cropRect = cropR
            }
        }

        // 3. HDR normalization: simple tone mapping for HDR content
        if isHDR {
            if let toned = toneMapHDR(image) {
                image = toned
                wasHDRToneMapped = true
            }
        }

        // 4. Color normalization: convert to sRGB
        if let normalized = normalizeColorSpace(image) {
            image = normalized
        }

        // 5. Resize to target width
        if let resized = resize(image, targetWidth: config.targetWidth) {
            image = resized
        }

        // 6. Luminance normalization (CLAHE-lite via histogram stretch)
        if let lumNorm = normalizeLuminance(image) {
            image = lumNorm
        }

        return NormalizedFrame(
            image: image,
            cropRect: cropRect,
            wasRotated: wasRotated,
            wasHDRToneMapped: wasHDRToneMapped
        )
    }

    // MARK: - Black-bar detection (spec §18)

    private func detectBlackBars(_ image: CGImage) -> CGRect? {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8

        guard bytesPerPixel >= 3 else { return nil }

        // Sample luminance of rows from top
        var topBar = 0
        var found = false
        for row in 0..<height {
            let lumSum = rowLuminanceSum(ptr, row: row, width: width, bytesPerRow: bytesPerRow, bpp: bytesPerPixel)
            let avgLum = lumSum / Double(width)
            if avgLum > 15 {  // threshold: not black
                topBar = row
                found = true
                break
            }
        }
        if !found { topBar = 0 }

        // Sample from bottom
        var bottomBar = height
        for row in stride(from: height - 1, through: 0, by: -1) {
            let lumSum = rowLuminanceSum(ptr, row: row, width: width, bytesPerRow: bytesPerRow, bpp: bytesPerPixel)
            let avgLum = lumSum / Double(width)
            if avgLum > 15 {
                bottomBar = row + 1
                break
            }
        }

        let topFrac = Double(topBar) / Double(height)
        let bottomFrac = Double(height - bottomBar) / Double(height)

        // Safety: don't crop more than maxCropFraction
        let safeTop = min(topFrac, config.maxCropFraction / 2)
        let safeBottom = min(bottomFrac, config.maxCropFraction / 2)

        // Only crop if bar is significant
        guard safeTop > config.blackBarThreshold || safeBottom > config.blackBarThreshold else {
            return nil
        }

        let cropTop = Int(safeTop * Double(height))
        let cropBottom = Int(safeBottom * Double(height))
        let cropHeight = max(1, height - cropTop - cropBottom)

        return CGRect(x: 0, y: cropTop, width: width, height: cropHeight)
    }

    private func rowLuminanceSum(
        _ ptr: UnsafePointer<UInt8>,
        row: Int, width: Int, bytesPerRow: Int, bpp: Int
    ) -> Double {
        var sum: Double = 0
        for col in 0..<width {
            let offset = row * bytesPerRow + col * bpp
            let r = Double(ptr[offset])
            let g = Double(ptr[offset + 1])
            let b = Double(ptr[offset + 2])
            sum += 0.299 * r + 0.587 * g + 0.114 * b
        }
        return sum
    }

    // MARK: - Image operations

    private func applyRotation(_ image: CGImage, degrees: Double) -> CGImage? {
        let radians = degrees * .pi / 180
        let ciImage = CIImage(cgImage: image)
        let transform = CGAffineTransform(rotationAngle: radians)
        let rotated = ciImage.transformed(by: transform)
        let ctx = CIContext()
        return ctx.createCGImage(rotated, from: rotated.extent)
    }

    private func cropImage(_ image: CGImage, to rect: CGRect) -> CGImage? {
        image.cropping(to: rect)
    }

    private func toneMapHDR(_ image: CGImage) -> CGImage? {
        // Simple tone map: apply gamma 2.2 approximation
        // For proper HDR: use Metal shader or vImage HDR processing
        let ciImage = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIToneCurve")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        // Simple s-curve approximation
        filter?.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        filter?.setValue(CIVector(x: 0.25, y: 0.15), forKey: "inputPoint1")
        filter?.setValue(CIVector(x: 0.5, y: 0.48), forKey: "inputPoint2")
        filter?.setValue(CIVector(x: 0.75, y: 0.80), forKey: "inputPoint3")
        filter?.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")
        guard let output = filter?.outputImage else { return nil }
        let ctx = CIContext()
        return ctx.createCGImage(output, from: output.extent)
    }

    private func normalizeColorSpace(_ image: CGImage) -> CGImage? {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    private func resize(_ image: CGImage, targetWidth: Int) -> CGImage? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }

        let targetH = max(1, (targetWidth * h) / w)
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: targetWidth,
                  height: targetH,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }

        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetH))
        return ctx.makeImage()
    }

    private func normalizeLuminance(_ image: CGImage) -> CGImage? {
        // Histogram stretch: map [p5..p95] to [0..255]
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let w = image.width
        let h = image.height
        let bpp = image.bitsPerPixel / 8
        guard bpp >= 3 else { return nil }
        let bpr = image.bytesPerRow
        let total = h * bpr

        // Compute luminance histogram
        var histogram = [Int](repeating: 0, count: 256)
        for row in 0..<h {
            for col in 0..<w {
                let off = row * bpr + col * bpp
                let r = Double(ptr[off])
                let g = Double(ptr[off + 1])
                let b = Double(ptr[off + 2])
                let lum = Int(0.299 * r + 0.587 * g + 0.114 * b)
                histogram[min(lum, 255)] += 1
            }
        }

        let pixCount = w * h
        let p5 = percentile(histogram, p: 0.05, total: pixCount)
        let p95 = percentile(histogram, p: 0.95, total: pixCount)
        let range = max(1, p95 - p5)

        // Apply stretch
        var outputBytes = [UInt8](repeating: 0, count: total)
        CFDataGetBytes(data, CFRange(location: 0, length: total), &outputBytes)

        for row in 0..<h {
            for col in 0..<w {
                let off = row * bpr + col * bpp
                for c in 0..<min(bpp, 3) {
                    let v = Double(outputBytes[off + c])
                    let stretched = min(255, max(0, Int(((v - Double(p5)) / Double(range)) * 255)))
                    outputBytes[off + c] = UInt8(stretched)
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(outputBytes) as CFData),
              let result = CGImage(
                  width: w, height: h,
                  bitsPerComponent: image.bitsPerComponent,
                  bitsPerPixel: image.bitsPerPixel,
                  bytesPerRow: bpr,
                  space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: image.bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }

        return result
    }

    private func percentile(_ histogram: [Int], p: Double, total: Int) -> Int {
        let target = Int(p * Double(total))
        var cum = 0
        for (i, count) in histogram.enumerated() {
            cum += count
            if cum >= target { return i }
        }
        return histogram.count - 1
    }
}
