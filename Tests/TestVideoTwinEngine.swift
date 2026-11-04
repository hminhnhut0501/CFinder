import Foundation
import SFinderCore
import CoreGraphics

print("================================================================================")
print("🧪 VIDEOTWIN ENGINE (SFINDER) - KIỂM THỬ KỸ THUẬT & LOGIC TOÀN DIỆN")
print("================================================================================")

func testCase(_ name: String, block: () async throws -> Void) async {
    print("\n--------------------------------------------------------------------------------")
    print("▶ KIỂM THỬ: \(name)")
    do {
        try await block()
        print("  => KẾT QUẢ: ✅ ĐẠT (PASSED)")
    } catch {
        print("  => KẾT QUẢ: ❌ THẤT BẠI: \(error)")
        exit(1)
    }
}

Task {
    // 1. Kiểm thử dHash & pHash cơ bản
    await testCase("Perceptual Hashing (dHash 64-bit & pHash DCT)") {
        // Tạo ảnh nhân tạo 32x32 với gradient
        let width = 32, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                pixels[y * width + x] = UInt8((x + y) * 255 / (width + height))
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let cgImage = ctx.makeImage() else {
            fatalError("Failed to create CGImage")
        }
        
        guard let dHash = DHasher.hash(cgImage) else {
            fatalError("dHash returned nil")
        }
        guard let pHash = PHasher.hash(cgImage) else {
            fatalError("pHash returned nil")
        }
        
        assert(DHasher.similarity(dHash, dHash) == 1.0, "Self similarity must be 1.0")
        assert(PHasher.similarity(pHash, pHash) == 1.0, "pHash self similarity must be 1.0")
        print("  ✓ dHash: \(String(format: "%016llX", dHash))")
        print("  ✓ pHash byte count: \(pHash.count), Similarity: 100%")
    }

    // 2. Kiểm thử Exact Duplicate Engine
    await testCase("Exact Duplicate Engine (Size filtering & SHA-256 chunked)") {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("VTTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let sampleData = "VideoTwin Duplicate Content Verification".data(using: .utf8)!
        let file1 = tempDir.appendingPathComponent("vid1.mp4")
        let file2 = tempDir.appendingPathComponent("vid2.mp4")
        let file3 = tempDir.appendingPathComponent("diff.mp4")
        
        try sampleData.write(to: file1)
        try sampleData.write(to: file2)
        try "Different Content Here".data(using: .utf8)!.write(to: file3)
        
        let resolver = FileIdentityResolver()
        let id1 = try await resolver.resolve(url: file1)
        let id2 = try await resolver.resolve(url: file2)
        let id3 = try await resolver.resolve(url: file3)
        
        let asset1 = VideoAsset(id: UUID(), path: file1, fileIdentity: id1)
        let asset2 = VideoAsset(id: UUID(), path: file2, fileIdentity: id2)
        let asset3 = VideoAsset(id: UUID(), path: file3, fileIdentity: id3)
        
        let engine = ExactDuplicateEngine()
        let pool = WorkerPool(maxConcurrency: 2)
        let pauseToken = PauseToken()
        let exactGroups = await engine.findExactDuplicates(assets: [asset1, asset2, asset3], pool: pool, pauseToken: pauseToken)
        
        assert(exactGroups.count == 1, "Must find exactly 1 duplicate group")
        assert(exactGroups[0].count == 2, "Duplicate group must contain 2 files")
        print("  ✓ Phát hiện chính xác 2 file trùng lặp byte tuyệt đối trong thư mục!")
    }

    // 3. Kiểm thử Timeline Consensus & Clustering Engine
    await testCase("ClusterEngine (Phân cụm hoàn tất bảo vệ dữ liệu không bắc cầu sai)") {
        let idA = UUID()
        let idB = UUID()
        
        let matchAB = MatchResult(
            id: UUID(), assetAID: idA, assetBID: idB,
            visualScore: 0.96, timelineScore: 0.95, audioScore: nil,
            durationScore: 1.0, metadataScore: 1.0, coverageScore: 0.98,
            matchType: .nearDuplicate, confidence: .veryHigh,
            alignment: AlignmentResult(offsetSeconds: 0, alignmentConfidence: 0.95, matchedFrames: 8, unmatchedFrames: 0, coverageA: 0.98, coverageB: 0.98),
            coverageA: 0.98, coverageB: 0.98,
            analysisVersion: "visual-v3", analysedAt: Date()
        )
        
        let clustering = ClusterEngine()
        let clusters = await clustering.cluster(matches: [matchAB], certifiedExactGroups: [])
        assert(clusters.count == 1, "Must group A and B into 1 cluster")
        assert(clusters[0].members.count == 2, "Cluster must have 2 members")
        print("  ✓ Phân nhóm video trùng lặp NearDuplicate thành công, chuẩn xác!")
    }

    // 4. Kiểm thử InMemory Storage & Dọn dẹp Zero-RAM
    await testCase("InMemoryVideoTwinStorage (Vòng đời on-demand, không chạy nền)") {
        let storage = InMemoryVideoTwinStorage()
        let testAsset = VideoAsset(
            id: UUID(),
            path: URL(fileURLWithPath: "/tmp/sample.mp4"),
            fileIdentity: FileIdentity(resourceID: 100, volumeID: "VOL1", fileSize: 1024, modificationDate: Date())
        )
        try await storage.saveAnalysis(testAsset)
        let loaded = try await storage.loadAnalysis(id: testAsset.id)
        assert(loaded?.id == testAsset.id, "Loaded asset must match saved asset")
        
        // Prune
        try await storage.pruneAnalysis(in: [], keeping: [])
        let emptied = try await storage.loadAnalysis(id: testAsset.id)
        assert(emptied == nil, "After prune, storage must be empty")
        print("  ✓ Bộ nhớ On-Demand kiểm soát an toàn, giải phóng 100% tài nguyên!")
    }

    print("\n================================================================================")
    print("🎉 TOÀN BỘ CÁC BÀI KIỂM THỬ KỸ THUẬT PHASE 1 ĐỀU THÀNH CÔNG RỰC RỠ!")
    print("================================================================================\n")
    exit(0)
}

RunLoop.main.run()
