import Foundation
import Combine

/// Engine đo tốc độ Internet trực tiếp chuẩn xác cao
/// Tích hợp đo Ping (độ trễ), Jitter (dao động), Tải xuống (Download) và Tải lên (Upload)
@MainActor
public final class SpeedTestEngine: ObservableObject {
    public static let shared = SpeedTestEngine()
    
    // MARK: - Published State
    
    @Published public private(set) var phase: SpeedTestPhase = .idle
    @Published public private(set) var currentGaugeSpeed: Double = 0 // In Mbps for gauge animation
    @Published public private(set) var currentGaugeProgress: Double = 0 // 0.0 to 1.0
    
    @Published public private(set) var livePingMs: Double = 0
    @Published public private(set) var liveJitterMs: Double = 0
    @Published public private(set) var liveDownloadMbps: Double = 0
    @Published public private(set) var liveUploadMbps: Double = 0
    
    @Published public private(set) var lastResult: SpeedTestResult?
    @Published public private(set) var history: [SpeedTestResult] = []
    
    // MARK: - Internal Tasks & State
    
    private var testTask: Task<Void, Never>?
    private var activeSession: URLSession?
    
    private let historyStorageKey = "sfinder_speedtest_history_records"
    
    private init() {
        loadHistory()
    }
    
    // MARK: - History Persistence
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyStorageKey) else { return }
        do {
            let decoder = JSONDecoder()
            self.history = try decoder.decode([SpeedTestResult].self, from: data)
            self.lastResult = history.first
        } catch {
            self.history = []
        }
    }
    
    private func saveHistoryRecord(_ result: SpeedTestResult) {
        var updated = history
        updated.insert(result, at: 0)
        if updated.count > 20 {
            updated = Array(updated.prefix(20))
        }
        self.history = updated
        self.lastResult = result
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(updated)
            UserDefaults.standard.set(data, forKey: historyStorageKey)
        } catch {
            // Non-critical
        }
    }
    
    public func clearHistory() {
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: historyStorageKey)
    }
    
    // MARK: - Speed Test Execution
    
    public func startTest() {
        cancelTest()
        
        livePingMs = 0
        liveJitterMs = 0
        liveDownloadMbps = 0
        liveUploadMbps = 0
        currentGaugeSpeed = 0
        currentGaugeProgress = 0
        phase = .preparing
        
        testTask = Task {
            do {
                try await runSpeedTestFlow()
            } catch is CancellationError {
                self.phase = .idle
                self.currentGaugeSpeed = 0
                self.currentGaugeProgress = 0
            } catch {
                self.phase = .failed(error.localizedDescription)
                self.currentGaugeSpeed = 0
                self.currentGaugeProgress = 0
            }
        }
    }
    
    public func cancelTest() {
        testTask?.cancel()
        testTask = nil
        activeSession?.invalidateAndCancel()
        activeSession = nil
        if phase.isRunning {
            phase = .idle
        }
        currentGaugeSpeed = 0
        currentGaugeProgress = 0
    }
    
    // MARK: - Test Flow
    
    private func runSpeedTestFlow() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 10.0
        sessionConfig.timeoutIntervalForResource = 30.0
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: sessionConfig)
        self.activeSession = session
        defer {
            session.finishTasksAndInvalidate()
            self.activeSession = nil
        }
        
        // Step 1: Resolve PoP & IP
        let traceUrl = URL(string: "https://speed.cloudflare.com/cdn-cgi/trace")!
        var (clientIP, serverColo) = ("---", "Cloudflare Global CDN")
        if let (traceData, _) = try? await session.data(from: traceUrl),
           let traceText = String(data: traceData, encoding: .utf8) {
            for line in traceText.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: "=")
                if parts.count == 2 {
                    if parts[0] == "ip" { clientIP = parts[1] }
                    if parts[0] == "colo" { serverColo = "Cloudflare PoP (\(parts[1]))" }
                }
            }
        }
        
        try Task.checkCancellation()
        
        // Step 2: Measure Ping & Jitter (6 probes)
        var pings: [Double] = []
        let pingUrl = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
        
        for i in 1...6 {
            try Task.checkCancellation()
            let t0 = DispatchTime.now()
            var req = URLRequest(url: pingUrl)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            _ = try await session.data(for: req)
            let t1 = DispatchTime.now()
            let ms = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
            pings.append(ms)
            
            let currentMedian = pings.sorted()[pings.count / 2]
            self.livePingMs = currentMedian
            let prog = Double(i) / 6.0 * 0.15
            self.currentGaugeProgress = prog
            self.phase = .pinging(progress: prog, currentPingMs: currentMedian)
            
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms pause
        }
        
        let finalPing = pings.sorted()[pings.count / 2]
        self.livePingMs = finalPing
        
        // Calculate Jitter
        if pings.count > 1 {
            var diffSum: Double = 0
            for i in 1..<pings.count {
                diffSum += abs(pings[i] - pings[i - 1])
            }
            self.liveJitterMs = diffSum / Double(pings.count - 1)
        }
        
        try Task.checkCancellation()
        
        // Step 3: Measure Download Speed
        // Chunk sizes: 2MB test probe, then 10MB test, then 25MB test for sustained accuracy
        let downloadChunks: [Int] = [2_000_000, 10_000_000, 20_000_000]
        var totalDownBytes: Int64 = 0
        var totalDownTime: Double = 0
        
        for (idx, chunkSize) in downloadChunks.enumerated() {
            try Task.checkCancellation()
            let downUrl = URL(string: "https://speed.cloudflare.com/__down?bytes=\(chunkSize)")!
            var req = URLRequest(url: downUrl)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            
            let tStart = Date()
            let (data, _) = try await session.data(for: req)
            let tEnd = Date()
            let duration = max(0.05, tEnd.timeIntervalSince(tStart))
            
            let bytes = Int64(data.count)
            totalDownBytes += bytes
            totalDownTime += duration
            
            let instantMbps = (Double(bytes) * 8.0) / (duration * 1_000_000.0)
            let avgMbps = (Double(totalDownBytes) * 8.0) / (totalDownTime * 1_000_000.0)
            
            self.liveDownloadMbps = avgMbps
            self.currentGaugeSpeed = instantMbps
            
            let chunkProg = 0.15 + (Double(idx + 1) / Double(downloadChunks.count)) * 0.45
            self.currentGaugeProgress = chunkProg
            self.phase = .downloading(progress: chunkProg, currentMbps: instantMbps)
            
            // If connection is relatively slow (> 4s on first chunk), skip largest 20MB chunk to keep test responsive
            if idx == 1 && totalDownTime > 4.0 {
                break
            }
        }
        
        let finalDownloadMbps = max(0.1, (Double(totalDownBytes) * 8.0) / (totalDownTime * 1_000_000.0))
        self.liveDownloadMbps = finalDownloadMbps
        
        try Task.checkCancellation()
        
        // Step 4: Measure Upload Speed
        let uploadChunks: [Int] = [1_000_000, 4_000_000, 8_000_000]
        var totalUpBytes: Int64 = 0
        var totalUpTime: Double = 0
        
        let upUrl = URL(string: "https://speed.cloudflare.com/__up")!
        
        for (idx, size) in uploadChunks.enumerated() {
            try Task.checkCancellation()
            let dummyPayload = Data(count: size)
            var req = URLRequest(url: upUrl)
            req.httpMethod = "POST"
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.httpBody = dummyPayload
            
            let tStart = Date()
            _ = try await session.data(for: req)
            let tEnd = Date()
            let duration = max(0.05, tEnd.timeIntervalSince(tStart))
            
            totalUpBytes += Int64(size)
            totalUpTime += duration
            
            let instantMbps = (Double(size) * 8.0) / (duration * 1_000_000.0)
            let avgMbps = (Double(totalUpBytes) * 8.0) / (totalUpTime * 1_000_000.0)
            
            self.liveUploadMbps = avgMbps
            self.currentGaugeSpeed = instantMbps
            
            let upProg = 0.60 + (Double(idx + 1) / Double(uploadChunks.count)) * 0.40
            self.currentGaugeProgress = upProg
            self.phase = .uploading(progress: upProg, currentMbps: instantMbps)
            
            if idx == 1 && totalUpTime > 3.5 {
                break
            }
        }
        
        let finalUploadMbps = max(0.1, (Double(totalUpBytes) * 8.0) / (totalUpTime * 1_000_000.0))
        self.liveUploadMbps = finalUploadMbps
        
        // Step 5: Final Evaluation & Record
        let rating = NetworkQualityRating.evaluate(downloadMbps: finalDownloadMbps, pingMs: finalPing)
        let record = SpeedTestResult(
            id: UUID(),
            date: Date(),
            pingMs: finalPing,
            jitterMs: liveJitterMs,
            downloadMbps: finalDownloadMbps,
            uploadMbps: finalUploadMbps,
            serverLocation: serverColo,
            clientIP: clientIP,
            rating: rating
        )
        
        self.saveHistoryRecord(record)
        self.currentGaugeProgress = 1.0
        self.currentGaugeSpeed = finalDownloadMbps
        self.phase = .completed(record)
    }
}
