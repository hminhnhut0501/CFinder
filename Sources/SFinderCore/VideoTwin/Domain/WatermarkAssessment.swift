import Foundation

public struct WatermarkRegion: Codable, Hashable, Sendable {
    /// Normalized coordinates, origin at top left of the displayed frame.
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public struct WatermarkEvidence: Codable, Hashable, Sendable, Identifiable {
    public var id: Double { seconds }
    public let seconds: Double
    public let peerSeconds: Double
    public let region: WatermarkRegion
    public let text: String?
}

public struct WatermarkAssessment: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case detected, possible, noEvidence, unavailable }
    public let status: Status
    public let peerID: UUID
    public let checkedFrames: Int
    public let supportingFrames: Int
    public let evidence: [WatermarkEvidence]
    public let explanation: String
    public let comparableAlternative: Bool
    public var dismissed = false
    public var penalty: Float { status == .detected && !dismissed ? 45 : 0 }
}

public enum WatermarkPolicy {
    public static func dismissalKey(_ asset: VideoAsset) -> String {
        let identity = asset.fileIdentity
        return "\(identity.volumeID):\(identity.resourceID):\(identity.fileSize):\(identity.modificationDate.timeIntervalSince1970)"
    }
    public static func comparable(_ marked: VideoAsset, _ clean: VideoAsset) -> Bool {
        guard let a = marked.metadata?.videoStream, let b = clean.metadata?.videoStream,
              a.displayWidth > 0, a.displayHeight > 0, b.displayWidth > 0, b.displayHeight > 0 else { return false }
        let ratioA = Double(a.displayWidth) / Double(a.displayHeight)
        let ratioB = Double(b.displayWidth) / Double(b.displayHeight)
        guard abs(ratioA / ratioB - 1) < 0.01,
              Double(b.displayWidth) * Double(b.displayHeight) >= Double(a.displayWidth) * Double(a.displayHeight) * 0.75,
              clean.quality?.upscaleSuspicion == UpscaleSuspicion.none else { return false }
        guard let sharpA = marked.quality?.sharpness, let sharpB = clean.quality?.sharpness,
              sharpA.isFinite, sharpB.isFinite else { return false }
        return sharpB + 0.05 >= sharpA * 0.75
    }
}
