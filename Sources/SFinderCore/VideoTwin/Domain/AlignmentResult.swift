import Foundation

/// Result of temporal alignment between two videos.
public struct AlignmentResult: Sendable, Hashable, Codable {
    /// A starts at this many seconds into B (positive = B starts earlier)
    public let offsetSeconds: Double
    public let alignmentConfidence: Float
    public let matchedFrames: Int
    public let unmatchedFrames: Int
    /// Fraction of A covered by the aligned region (0...1)
    public let coverageA: Float
    /// Fraction of B covered by the aligned region (0...1)
    public let coverageB: Float

    public var formattedOffset: String {
        let sign = offsetSeconds >= 0 ? "+" : "-"
        let abs = Swift.abs(offsetSeconds)
        let min = Int(abs) / 60
        let sec = abs.truncatingRemainder(dividingBy: 60)
        return String(format: "%@%02d:%05.2f", sign, min, sec)
    }

    public init(offsetSeconds: Double, alignmentConfidence: Float, matchedFrames: Int, unmatchedFrames: Int, coverageA: Float, coverageB: Float) {
        self.offsetSeconds = offsetSeconds
        self.alignmentConfidence = alignmentConfidence
        self.matchedFrames = matchedFrames
        self.unmatchedFrames = unmatchedFrames
        self.coverageA = coverageA
        self.coverageB = coverageB
    }
}
