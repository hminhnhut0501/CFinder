import Foundation

public struct VideoScoringEngine: Sendable {
    
    public init() {}
    
    // MARK: - Quality Score Calculation
    
    public func scoreVideo(
        fileSize: Int64,
        durationSeconds: Double,
        video: VideoStreamDetail?,
        audio: AudioStreamDetail?
    ) -> VideoQualityScore {
        guard let v = video, v.width > 0, v.height > 0 else {
            return VideoQualityScore(
                overallScore: 0,
                visualFidelityScore: 0,
                storageEfficiencyScore: 0,
                audioFidelityScore: 0,
                bitsPerPixelFrame: 0,
                bppfHealth: .starved,
                adjustments: [ScoreAdjustment(aspect: "Dữ liệu", description: "Thiếu luồng hình ảnh", points: 0)],
                verdictSummary: "Tệp không chứa luồng video hợp lệ",
                isBloatedBitrate: false,
                isSuspectedUpscale: false
            )
        }
        
        var adjustments: [ScoreAdjustment] = []
        
        let fps = v.fps > 0 ? v.fps : 30.0
        let pixels = Double(v.width * v.height)
        
        // Calculate or estimate video bitrate
        var effectiveVideoBitrate = Double(v.bitrate)
        if effectiveVideoBitrate <= 0 && durationSeconds > 0 {
            let totalBps = (Double(fileSize) * 8.0) / durationSeconds
            let audioBps = Double(audio?.bitrate ?? 128_000)
            effectiveVideoBitrate = max(100_000, totalBps - audioBps)
        }
        
        // 1. Calculate BPPF (Bits per Pixel Frame)
        let bppf = (pixels > 0 && fps > 0) ? (effectiveVideoBitrate / (pixels * fps)) : 0.0
        
        // Codec classification
        let rawCodec = v.codec.lowercased()
        let isHEVC = rawCodec.contains("hevc") || rawCodec.contains("h265") || rawCodec.contains("hvc1")
        let isAV1 = rawCodec.contains("av01") || rawCodec.contains("av1")
        let isVP9 = rawCodec.contains("vp09") || rawCodec.contains("vp9")
        let isProRes = rawCodec.contains("apcn") || rawCodec.contains("apch") || rawCodec.contains("ap4h") || rawCodec.contains("prores")
        let isH264 = rawCodec.contains("avc1") || rawCodec.contains("h264") || rawCodec.contains("avc")
        
        // 2. Evaluate BPPF Health & Fake/Bloated Bitrate
        var bppfHealth: BPPFHealth = .optimal
        var bloatPenalty: Double = 0
        var isBloatedBitrate = false
        var isSuspectedUpscale = false
        
        if isProRes {
            if bppf < 0.20 {
                bppfHealth = .starved
                adjustments.append(ScoreAdjustment(aspect: "Bitrate", description: "ProRes bị nén dưới chuẩn", points: -10))
            } else {
                bppfHealth = .optimal
            }
        } else if isAV1 || isHEVC {
            if bppf < 0.020 {
                bppfHealth = .starved
                let penalty = min(20.0, (0.020 - bppf) / 0.015 * 20.0)
                adjustments.append(ScoreAdjustment(aspect: "Nén vỡ", description: "Bitrate quá thấp cho HEVC/AV1, dễ bị vỡ hình", points: -penalty))
            } else if bppf <= 0.085 {
                bppfHealth = .optimal
                adjustments.append(ScoreAdjustment(aspect: "Hiệu quả", description: "Tỷ lệ Bitrate/Pixel tối ưu tuyệt đối", points: 15))
            } else if bppf <= 0.130 {
                bppfHealth = .high
            } else {
                bppfHealth = bppf > 0.220 ? .excessiveBloat : .bloated
                isBloatedBitrate = true
                bloatPenalty = min(35.0, ((bppf - 0.130) / 0.100) * 25.0)
                adjustments.append(ScoreAdjustment(aspect: "Bơm Bitrate Ảo", description: "Bitrate bị đẩy cao bất thường so với HEVC, gây lãng phí dung lượng nặng", points: -bloatPenalty))
            }
        } else if isH264 || isVP9 {
            if bppf < 0.035 {
                bppfHealth = .starved
                let penalty = min(22.0, (0.035 - bppf) / 0.025 * 22.0)
                adjustments.append(ScoreAdjustment(aspect: "Nén vỡ", description: "Bitrate quá thấp cho H.264, xuất hiện khối vuông macroblock", points: -penalty))
            } else if bppf <= 0.130 {
                bppfHealth = .optimal
                adjustments.append(ScoreAdjustment(aspect: "Hiệu quả", description: "Tỷ lệ Bitrate/Pixel chuẩn cho H.264", points: 12))
            } else if bppf <= 0.200 {
                bppfHealth = .high
            } else {
                bppfHealth = bppf > 0.320 ? .excessiveBloat : .bloated
                isBloatedBitrate = true
                bloatPenalty = min(40.0, ((bppf - 0.200) / 0.150) * 30.0)
                adjustments.append(ScoreAdjustment(aspect: "Bơm Bitrate Ảo", description: "Bitrate quá lớn so với H.264 mà không tăng độ sắc nét thực tế", points: -bloatPenalty))
            }
        } else {
            // Legacy MPEG-4 / DivX / other
            adjustments.append(ScoreAdjustment(aspect: "Codec Cũ", description: "Thuật toán nén lỗi thời", points: -15))
            if bppf > 0.300 {
                isBloatedBitrate = true
                bppfHealth = .bloated
                bloatPenalty = 25.0
            }
        }
        
        // 3. Fake Upscale Check
        let maxDim = max(v.displayWidth, v.displayHeight)
        if maxDim >= 1920 && bppf < 0.015 && !isProRes {
            isSuspectedUpscale = true
            adjustments.append(ScoreAdjustment(aspect: "Upscale Ảo", description: "Độ phân giải danh định cao nhưng Bitrate không đủ dữ liệu thật", points: -20))
        }
        
        // 4. Calculate Visual Fidelity Score (0...100)
        var visualScore: Double = 0
        if maxDim >= 3840 { visualScore += 35 }
        else if maxDim >= 2560 { visualScore += 28 }
        else if maxDim >= 1920 { visualScore += 22 }
        else if maxDim >= 1280 { visualScore += 16 }
        else { visualScore += 8 }
        
        if v.isHDR || v.bitDepth > 8 {
            visualScore += 10
            adjustments.append(ScoreAdjustment(aspect: "Dải động & Màu", description: "10-bit / HDR tái tạo màu mượt mà không bị bệt dải", points: 10))
        }
        
        if fps >= 50.0 {
            visualScore += 6
            adjustments.append(ScoreAdjustment(aspect: "Khung hình", description: "\(Int(fps))fps mượt mà", points: 6))
        }
        
        if v.isVFR {
            visualScore -= 5
            adjustments.append(ScoreAdjustment(aspect: "Khung hình biến thiên", description: "VFR dễ gây giật khung hình khi dựng/phát", points: -5))
        }
        
        if isSuspectedUpscale {
            visualScore -= 20
        }
        
        // 5. Calculate Storage Efficiency Score (0...100)
        var efficiencyScore: Double = 50.0
        if isAV1 {
            efficiencyScore += 30
            adjustments.append(ScoreAdjustment(aspect: "Thế hệ Codec", description: "AV1 thế hệ mới nhất, hiệu suất nén vượt trội", points: 15))
        } else if isHEVC {
            efficiencyScore += 25
            adjustments.append(ScoreAdjustment(aspect: "Thế hệ Codec", description: "HEVC (H.265) nén chuẩn, tiết kiệm 50% dung lượng so với H.264", points: 12))
        } else if isVP9 {
            efficiencyScore += 18
        } else if isH264 {
            efficiencyScore += 10
        } else if isProRes {
            efficiencyScore = 30 // ProRes trades space for speed
        } else {
            efficiencyScore -= 20
        }
        
        // Deduct bloat penalty from efficiency
        efficiencyScore = max(0, efficiencyScore - bloatPenalty)
        
        // 6. Calculate Audio Fidelity Score (0...100)
        var audioScore: Double = 50.0
        if let a = audio {
            if a.channels >= 6 {
                audioScore += 25
                adjustments.append(ScoreAdjustment(aspect: "Âm thanh", description: "\(a.channelLayout) đa kênh sống động", points: 10))
            } else if a.channels == 2 {
                audioScore += 15
            }
            
            let aBitrate = a.bitrate ?? 128_000
            if aBitrate >= 320_000 {
                audioScore += 20
            } else if aBitrate >= 192_000 {
                audioScore += 12
            }
            
            let audioCodec = a.codec.lowercased()
            if audioCodec.contains("flac") || audioCodec.contains("alac") || audioCodec.contains("pcm") || audioCodec.contains("truehd") {
                audioScore += 20
                adjustments.append(ScoreAdjustment(aspect: "Âm thanh", description: "Âm thanh Lossless không nén", points: 12))
            }
        }
        
        // 7. Overall Score Composite
        let visualNorm = min(100.0, max(0.0, visualScore * 1.8))
        let effNorm = min(100.0, max(0.0, efficiencyScore))
        let audioNorm = min(100.0, max(0.0, audioScore))
        
        var composite = (visualNorm * 0.45) + (effNorm * 0.35) + (audioNorm * 0.20)
        if isBloatedBitrate {
            composite = max(20.0, composite - bloatPenalty * 0.5)
        }
        let finalOverall = min(100.0, max(0.0, composite))
        
        // 8. Verdict Summary Sentence
        let summary: String
        if isBloatedBitrate {
            summary = "Cảnh báo: Video có Bitrate quá cao (\(String(format: "%.2f", bppf)) bppf) so với độ phân giải thực, làm phình dung lượng vô ích mà không cải thiện độ nét."
        } else if isSuspectedUpscale {
            summary = "Nghi vấn: Video dường như được phóng to (upscale) từ nguồn phân giải thấp do bitrate không tương xứng."
        } else if isHEVC && (v.isHDR || v.bitDepth > 8) {
            summary = "Xuất sắc: Chuẩn nén HEVC 10-bit HDR cao cấp, cân bằng hoàn hảo giữa độ nét điện ảnh và dung lượng tối ưu."
        } else if bppfHealth == .optimal {
            summary = "Tối ưu: Bitrate và mật độ điểm ảnh đạt điểm vàng khoa học, hình ảnh trong trẻo không lãng phí dung lượng."
        } else {
            summary = "Chất lượng tiêu chuẩn, phù hợp lưu trữ và phát thông thường."
        }
        
        return VideoQualityScore(
            overallScore: finalOverall.rounded(),
            visualFidelityScore: visualNorm.rounded(),
            storageEfficiencyScore: effNorm.rounded(),
            audioFidelityScore: audioNorm.rounded(),
            bitsPerPixelFrame: bppf,
            bppfHealth: bppfHealth,
            adjustments: adjustments,
            verdictSummary: summary,
            isBloatedBitrate: isBloatedBitrate,
            isSuspectedUpscale: isSuspectedUpscale
        )
    }
    
    // MARK: - Multi-video Comparison & Verdict
    
    public func compareVideos(reports: [VideoDetailedReport]) -> ComparisonVerdict? {
        guard reports.count >= 2 else { return nil }
        
        // Sort descending by overall score
        let sorted = reports.sorted { $0.score.overallScore > $1.score.overallScore }
        guard let winner = sorted.first else { return nil }
        let runnerUp = sorted[1]
        
        let sizeDiff = runnerUp.fileSize - winner.fileSize
        let isWinnerSmaller = sizeDiff > 0
        
        var headline = "🏆 Video khuyến nghị: \(winner.fileName)"
        var explanation = ""
        
        if runnerUp.score.isBloatedBitrate && !winner.score.isBloatedBitrate {
            let savedStr = ByteCountFormatter.string(fromByteCount: abs(sizeDiff), countStyle: .file)
            headline = "🏆 Khuyên giữ: \(winner.fileName) (Tránh lãng phí dung lượng)"
            explanation = "Bản '\(runnerUp.fileName)' bị bơm Bitrate ảo (\(String(format: "%.2f", runnerUp.score.bitsPerPixelFrame)) bppf) làm phình dung lượng mà không tăng độ sắc nét. Giữ bản '\(winner.fileName)' giúp bạn tiết kiệm \(savedStr) mà chất lượng hiển thị tương đương hoặc vượt trội."
        } else if winner.score.visualFidelityScore > runnerUp.score.visualFidelityScore && isWinnerSmaller {
            let savedStr = ByteCountFormatter.string(fromByteCount: sizeDiff, countStyle: .file)
            headline = "🏆 Khuyên giữ: \(winner.fileName) (Nét hơn & Nhẹ hơn)"
            explanation = "Nhờ công nghệ nén tiên tiến hơn (\(winner.primaryVideo?.humanCodec ?? "HEVC")), bản này cho độ nét cao hơn (điểm hình ảnh: \(Int(winner.score.visualFidelityScore))) trong khi tiết kiệm thêm \(savedStr) dung lượng so với bản còn lại."
        } else {
            headline = "🏆 Khuyên giữ: \(winner.fileName) (Điểm tổng thể: \(Int(winner.score.overallScore))/100)"
            explanation = "Bản này đạt điểm số vượt trội về độ ổn định khung hình, chuẩn không gian màu và âm thanh (\(Int(winner.score.overallScore)) điểm so với \(Int(runnerUp.score.overallScore)) điểm của bản đối chiếu)."
        }
        
        return ComparisonVerdict(
            winnerURL: winner.url,
            headline: headline,
            explanation: explanation,
            storageDifferenceBytes: sizeDiff,
            isWinnerMoreEfficient: isWinnerSmaller
        )
    }
}
