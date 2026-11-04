import Foundation
import SFinderCore

print("================================================================================")
print("🧪 VIDEO SCORING & INTELLIGENT COMPARISON ENGINE - UNIT TEST")
print("================================================================================")

let scorer = VideoScoringEngine()

// Test 1: Fake/Bloated Bitrate Detection (720p H.264 blown up to 45 Mbps vs 1080p HEVC at 5 Mbps)
print("\n▶ TEST 1: Phát hiện Bơm Bitrate Ảo (Bloated Bitrate)")
let bloated720p = VideoStreamDetail(
    index: 0,
    codec: "avc1",
    humanCodec: "H.264 / AVC",
    profile: nil,
    bitDepth: 8,
    chromaSubsampling: "4:2:0",
    width: 1280,
    height: 720,
    displayWidth: 1280,
    displayHeight: 720,
    aspectRatio: "16:9",
    fps: 30.0,
    isVFR: false,
    bitrate: 45_000_000, // 45 Mbps for 720p = BPPF ~ 1.62! Heavy bloat!
    isHDR: false,
    colorPrimaries: nil,
    transferCharacteristics: nil,
    colorSpace: nil
)

let scoreBloated = scorer.scoreVideo(
    fileSize: 4_500_000_000,
    durationSeconds: 800,
    video: bloated720p,
    audio: nil
)

print("  - 720p Bloated Video BPPF: \(String(format: "%.3f", scoreBloated.bitsPerPixelFrame))")
print("  - Health: \(scoreBloated.bppfHealth.rawValue)")
print("  - Is Bloated: \(scoreBloated.isBloatedBitrate)")
print("  - Overall Score: \(scoreBloated.overallScore)/100")
print("  - Adjustments: \(scoreBloated.adjustments.map { "\($0.aspect): \($0.points)" })")

assert(scoreBloated.isBloatedBitrate == true, "Must detect bloated bitrate!")
assert(scoreBloated.bppfHealth == .excessiveBloat || scoreBloated.bppfHealth == .bloated, "Must be classified as bloated!")

// Test 2: Optimal HEVC 10-bit HDR video
print("\n▶ TEST 2: Video HEVC 10-bit HDR Chuẩn Tối ưu")
let optimal1080p = VideoStreamDetail(
    index: 0,
    codec: "hvc1",
    humanCodec: "HEVC / H.265",
    profile: nil,
    bitDepth: 10,
    chromaSubsampling: "4:2:0",
    width: 1920,
    height: 1080,
    displayWidth: 1920,
    displayHeight: 1080,
    aspectRatio: "16:9",
    fps: 60.0,
    isVFR: false,
    bitrate: 6_000_000, // 6 Mbps for 1080p 60fps HEVC = BPPF ~ 0.048 (Sweet spot!)
    isHDR: true,
    colorPrimaries: "ITU-R BT.2020",
    transferCharacteristics: "HDR10 (PQ)",
    colorSpace: nil
)

let scoreOptimal = scorer.scoreVideo(
    fileSize: 600_000_000,
    durationSeconds: 800,
    video: optimal1080p,
    audio: AudioStreamDetail(
        index: 1,
        codec: "ec-3",
        humanCodec: "Dolby Digital Plus",
        channels: 6,
        channelLayout: "5.1 Surround",
        sampleRate: 48000,
        bitDepth: 24,
        bitrate: 448_000
    )
)

print("  - 1080p HEVC BPPF: \(String(format: "%.3f", scoreOptimal.bitsPerPixelFrame))")
print("  - Health: \(scoreOptimal.bppfHealth.rawValue)")
print("  - Is Bloated: \(scoreOptimal.isBloatedBitrate)")
print("  - Overall Score: \(scoreOptimal.overallScore)/100")
print("  - Verdict: \(scoreOptimal.verdictSummary)")

assert(scoreOptimal.isBloatedBitrate == false, "Must not be bloated!")
assert(scoreOptimal.bppfHealth == .optimal, "Must be optimal health!")
assert(scoreOptimal.overallScore > scoreBloated.overallScore, "Optimal HEVC must beat bloated 720p!")

// Test 3: Multi-video Comparison Verdict
print("\n▶ TEST 3: Đưa ra Kết luận So sánh Đối đầu (Comparison Verdict)")
let reportA = VideoDetailedReport(
    url: URL(fileURLWithPath: "/test/Movie_1080p_HEVC_HDR.mp4"),
    fileName: "Movie_1080p_HEVC_HDR.mp4",
    fileSize: 600_000_000,
    container: "MP4",
    durationSeconds: 800,
    totalBitrate: 6_000_000,
    videoStreams: [optimal1080p],
    audioStreams: [],
    creationDate: Date(),
    score: scoreOptimal
)

let reportB = VideoDetailedReport(
    url: URL(fileURLWithPath: "/test/Movie_720p_Bloated_45Mbps.mp4"),
    fileName: "Movie_720p_Bloated_45Mbps.mp4",
    fileSize: 4_500_000_000,
    container: "MP4",
    durationSeconds: 800,
    totalBitrate: 45_000_000,
    videoStreams: [bloated720p],
    audioStreams: [],
    creationDate: Date(),
    score: scoreBloated
)

let verdict = scorer.compareVideos(reports: [reportA, reportB])
assert(verdict != nil, "Verdict must not be nil")
print("  - Winner: \(verdict!.winnerURL.lastPathComponent)")
print("  - Headline: \(verdict!.headline)")
print("  - Explanation: \(verdict!.explanation)")
assert(verdict!.winnerURL == reportA.url, "Report A (HEVC) must win over bloated 720p!")

print("\n================================================================================")
print("✅ TẤT CẢ KIỂM THỬ GIAI ĐOẠN 1 ĐÃ VƯỢT QUA XUẤT SẮC!")
print("================================================================================")
