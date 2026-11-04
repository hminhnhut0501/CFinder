import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import OSLog

/// Extracts video metadata natively via AVFoundation (hardware-accelerated on Apple Silicon).
/// 100% Native macOS implementation with zero external CLI or library dependencies.
public actor NativeMetadataEngine {
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "probe")

    public init() {}

    // MARK: - Public API

    public func probe(asset: VideoAsset) async -> VideoMetadata? {
        return await probeWithAVFoundation(url: asset.path)
    }

    public func probe(url: URL) async -> VideoMetadata? {
        return await probeWithAVFoundation(url: url)
    }

    // MARK: - AVFoundation probe

    private func probeWithAVFoundation(url: URL) async -> VideoMetadata? {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])

        // Load tracks asynchronously
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            logger.debug("AVFoundation tracks load failed for \(url.lastPathComponent): \(error)")
            return nil
        }

        let container = url.pathExtension.lowercased()

        // File attributes
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0
        let creationDate = attrs?[.creationDate] as? Date
        let modDate = attrs?[.modificationDate] as? Date

        // Video stream
        var videoStream: VideoStreamMetadata?
        if let videoTrack = tracks.first {
            videoStream = await probeVideoTrack(videoTrack, asset: asset)
        }

        // Audio stream
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            audioTracks = []
        }
        var audioStream: AudioStreamMetadata?
        if let audioTrack = audioTracks.first {
            audioStream = await probeAudioTrack(audioTrack)
        }

        guard videoStream != nil || audioStream != nil else { return nil }

        return VideoMetadata(
            container: container,
            fileSize: fileSize,
            creationDate: creationDate,
            modificationDate: modDate,
            videoStream: videoStream,
            audioStream: audioStream
        )
    }

    private func probeVideoTrack(_ track: AVAssetTrack, asset: AVURLAsset) async -> VideoStreamMetadata? {
        do {
            let duration = try await asset.load(.duration)
            let nominalFPS = try await track.load(.nominalFrameRate)
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let estimatedBitrate = try await track.load(.estimatedDataRate)

            // Calculate display size after transform
            let displaySize = naturalSize.applying(preferredTransform)
            let displayWidth = abs(Int(displaySize.width.rounded()))
            let displayHeight = abs(Int(displaySize.height.rounded()))

            // Rotation from transform
            let rotation = atan2(preferredTransform.b, preferredTransform.a) * (180 / .pi)

            // Codec from format descriptions
            let formatDescriptions = try await track.load(.formatDescriptions)
            var codec = "unknown"
            var isHDR = false
            var colorPrimaries: String?
            var transferCharacteristics: String?
            let colorSpace: String? = nil
            let pixelFormat: String? = nil
            var bitDepth: Int?

            if let desc = formatDescriptions.first {
                let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                codec = fourCCToString(mediaSubType)

                // HDR detection via transfer characteristics
                let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any]
                transferCharacteristics = extensions?[kCMFormatDescriptionExtension_TransferFunction as String] as? String
                colorPrimaries = extensions?[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String

                if let tc = transferCharacteristics {
                    isHDR = tc.contains("2084") || tc.contains("2100") || tc == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
                }

                if let pf = extensions?[kCMFormatDescriptionExtension_Depth as String] as? Int {
                    bitDepth = pf > 8 ? pf : 8
                }
            }

            return VideoStreamMetadata(
                codec: codec,
                codecProfile: nil,
                codecLevel: nil,
                pixelFormat: pixelFormat,
                bitDepth: bitDepth ?? 8,
                width: Int(naturalSize.width.rounded()),
                height: Int(naturalSize.height.rounded()),
                displayWidth: displayWidth > 0 ? displayWidth : Int(naturalSize.width.rounded()),
                displayHeight: displayHeight > 0 ? displayHeight : Int(naturalSize.height.rounded()),
                rotation: Double(rotation.rounded()),
                nominalFPS: Double(nominalFPS),
                averageFPS: Double(nominalFPS),
                isVFR: false,
                bitrate: Int64(estimatedBitrate),
                isHDR: isHDR,
                colorPrimaries: colorPrimaries,
                transferCharacteristics: transferCharacteristics,
                colorSpace: colorSpace,
                duration: duration
            )
        } catch {
            logger.warning("Video track probe error: \(error)")
            return nil
        }
    }

    private func probeAudioTrack(_ track: AVAssetTrack) async -> AudioStreamMetadata? {
        do {
            let estimatedBitrate = try await track.load(.estimatedDataRate)
            let formatDescriptions = try await track.load(.formatDescriptions)

            var codec = "unknown"
            var channels = 0
            var sampleRate: Double = 0

            if let desc = formatDescriptions.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                sampleRate = asbd.pointee.mSampleRate
                channels = Int(asbd.pointee.mChannelsPerFrame)
                let subType = CMFormatDescriptionGetMediaSubType(desc)
                codec = fourCCToString(subType)
            }

            return AudioStreamMetadata(
                codec: codec,
                channels: channels,
                sampleRate: sampleRate,
                bitrate: Int64(estimatedBitrate)
            )
        } catch {
            logger.warning("Audio track probe error: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    private func fourCCToString(_ fourCC: FourCharCode) -> String {
        let bytes = [
            UInt8((fourCC >> 24) & 0xFF),
            UInt8((fourCC >> 16) & 0xFF),
            UInt8((fourCC >> 8) & 0xFF),
            UInt8(fourCC & 0xFF)
        ]
        let str = String(bytes: bytes, encoding: .ascii) ?? "????"
        return str.trimmingCharacters(in: .whitespaces)
    }
}
