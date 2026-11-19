import Foundation
import OSLog

public struct FFmpegProgress: Sendable {
    public let frame: Int64
    public let fps: Double
    public let currentTimeSeconds: Double
    public let totalTimeSeconds: Double
    public let progressRatio: Double // 0.0 to 1.0
    public let speed: Double // e.g. 5.2x
    public let bitrate: String
    public let etaSeconds: Double?
}

public struct FFmpegExecutionResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let executionDuration: TimeInterval
    
    public var isSuccess: Bool {
        return exitCode == 0
    }
}

public enum FFmpegError: LocalizedError, Sendable {
    case ffmpegNotFound
    case ffprobeNotFound
    case executionFailed(exitCode: Int32, errorOutput: String)
    case cancelled
    case invalidOutput
    
    public var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "Không tìm thấy công cụ ffmpeg trên hệ thống. Vui lòng cài đặt qua Homebrew (brew install ffmpeg)."
        case .ffprobeNotFound:
            return "Không tìm thấy công cụ ffprobe trên hệ thống. Vui lòng cài đặt qua Homebrew (brew install ffmpeg)."
        case .executionFailed(let code, let err):
            return "Xử lý ffmpeg thất bại (Exit code: \(code)): \(err)"
        case .cancelled:
            return "Tiến trình chuyển đổi video đã bị người dùng hủy."
        case .invalidOutput:
            return "Đầu ra của video không hợp lệ hoặc dữ liệu bị hỏng."
        }
    }
}

public final class FFmpegManager: @unchecked Sendable {
    public static let shared = FFmpegManager()
    private let logger = Logger(subsystem: "com.sfinder.core", category: "FFmpegManager")
    
    private let commonSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]
    
    private var cachedFFmpegPath: String?
    private var cachedFFprobePath: String?
    private var cachedHardwareEncoders: Set<String>?
    private let lock = NSLock()
    
    private init() {}
    
    // MARK: - Binary Location Discovery
    
    public func locateFFmpeg() -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cachedFFmpegPath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        
        if let path = findExecutable(name: "ffmpeg") {
            cachedFFmpegPath = path
            logger.info("Found ffmpeg at: \(path)")
            return path
        }
        
        logger.error("ffmpeg executable not found in known paths.")
        return nil
    }
    
    public func locateFFprobe() -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cachedFFprobePath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        
        if let path = findExecutable(name: "ffprobe") {
            cachedFFprobePath = path
            logger.info("Found ffprobe at: \(path)")
            return path
        }
        
        logger.error("ffprobe executable not found in known paths.")
        return nil
    }
    
    private func findExecutable(name: String) -> String? {
        let fm = FileManager.default
        
        // 1. Check App Bundle Resources if bundled
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent(name).path
            if fm.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }
        
        // 2. Check standard Homebrew / Unix search paths
        for dir in commonSearchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        
        // 3. Fallback: Lookup via PATH environment
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            let paths = envPath.split(separator: ":").map(String.init)
            for dir in paths {
                let candidate = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Hardware Encoder Detection
    
    public func getAvailableEncoders() -> Set<String> {
        lock.lock()
        if let cached = cachedHardwareEncoders {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        guard let ffmpegPath = locateFFmpeg() else {
            return []
        }
        
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = ["-encoders"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        var foundEncoders = Set<String>()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                if output.contains("h264_videotoolbox") { foundEncoders.insert("h264_videotoolbox") }
                if output.contains("hevc_videotoolbox") { foundEncoders.insert("hevc_videotoolbox") }
                if output.contains("libx264") { foundEncoders.insert("libx264") }
                if output.contains("libx265") { foundEncoders.insert("libx265") }
                if output.contains("aac") { foundEncoders.insert("aac") }
            }
        } catch {
            logger.error("Failed to query ffmpeg encoders: \(error.localizedDescription)")
        }
        
        lock.lock()
        cachedHardwareEncoders = foundEncoders
        lock.unlock()
        
        return foundEncoders
    }
    
    public var hasVideoToolboxH264: Bool {
        return getAvailableEncoders().contains("h264_videotoolbox")
    }
    
    // MARK: - Execute ffprobe
    
    public func runFFprobe(arguments: [String]) async throws -> String {
        guard let ffprobePath = locateFFprobe() else {
            throw FFmpegError.ffprobeNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffprobePath)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                let outString = String(data: outData, encoding: .utf8) ?? ""
                let errString = String(data: errData, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: outString)
                } else {
                    continuation.resume(throwing: FFmpegError.executionFailed(exitCode: process.terminationStatus, errorOutput: errString))
                }
            }
        }
    }
    
    // MARK: - Execute ffmpeg with streaming progress
    
    public func runFFmpeg(
        arguments: [String],
        totalDurationSeconds: Double? = nil,
        onProgress: (@Sendable (FFmpegProgress) -> Void)? = nil,
        onCancel: (@Sendable () -> Void)? = nil
    ) async throws -> FFmpegExecutionResult {
        guard let ffmpegPath = locateFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }
        
        let startTime = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.standardInput = FileHandle.nullDevice
        
        var effectiveArgs: [String] = []
        if !arguments.contains("-nostdin") {
            effectiveArgs.append("-nostdin")
        }
        effectiveArgs.append(contentsOf: arguments)
        process.arguments = effectiveArgs
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Handle cancellation
        let isCancelled = SynchronizedValue(false)
        let processRef = SynchronizedValue<Process?>(process)
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrCollector = FFmpegDataCollector()
                
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if !chunk.isEmpty {
                        stderrCollector.append(chunk)
                    }
                }
                
                let parser = FFmpegProgressParser(totalDurationSeconds: totalDurationSeconds, onProgress: onProgress)
                stdoutHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        parser.parse(chunk: data)
                    }
                }
                
                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                
                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    
                    let exitCode = proc.terminationStatus
                    let duration = Date().timeIntervalSince(startTime)
                    let errString = stderrCollector.asString()
                    
                    if isCancelled.get() {
                        continuation.resume(throwing: FFmpegError.cancelled)
                    } else if exitCode == 0 {
                        let res = FFmpegExecutionResult(
                            exitCode: exitCode,
                            standardOutput: "",
                            standardError: errString,
                            executionDuration: duration
                        )
                        continuation.resume(returning: res)
                    } else {
                        continuation.resume(throwing: FFmpegError.executionFailed(exitCode: exitCode, errorOutput: errString))
                    }
                }
            }
        } onCancel: {
            isCancelled.set(true)
            if let p = processRef.get(), p.isRunning {
                p.terminate()
            }
            onCancel?()
        }
    }
}

// MARK: - Safe Thread-safe Progress & Output Collectors

private final class FFmpegDataCollector: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    
    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }
    
    func asString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class FFmpegProgressParser: @unchecked Sendable {
    private let totalDurationSeconds: Double?
    private let onProgress: (@Sendable (FFmpegProgress) -> Void)?
    private var buffer = Data()
    private var currentFrame: Int64 = 0
    private var currentFps: Double = 0.0
    private var currentSpeed: Double = 1.0
    private var currentBitrate: String = ""
    private var currentTimeUs: Int64 = 0
    private let lock = NSLock()
    
    init(totalDurationSeconds: Double?, onProgress: (@Sendable (FFmpegProgress) -> Void)?) {
        self.totalDurationSeconds = totalDurationSeconds
        self.onProgress = onProgress
    }
    
    func parse(chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        
        buffer.append(chunk)
        
        while let newlineRange = buffer.range(of: Data([0x0A])) { // \n
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)
            
            if let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let val = parts[1].trimmingCharacters(in: .whitespaces)
                    
                    switch key {
                    case "frame":
                        currentFrame = Int64(val) ?? currentFrame
                    case "fps":
                        currentFps = Double(val) ?? currentFps
                    case "speed":
                        let cleaned = val.replacingOccurrences(of: "x", with: "").trimmingCharacters(in: .whitespaces)
                        currentSpeed = Double(cleaned) ?? currentSpeed
                    case "bitrate":
                        currentBitrate = val
                    case "out_time_us":
                        currentTimeUs = Int64(val) ?? currentTimeUs
                    case "progress":
                        let currentTimeSec = Double(currentTimeUs) / 1_000_000.0
                        let totalDuration = totalDurationSeconds ?? (currentTimeSec > 0 ? currentTimeSec : 1.0)
                        let ratio = totalDuration > 0 ? min(1.0, max(0.0, currentTimeSec / totalDuration)) : 0.0
                        
                        var eta: Double? = nil
                        if currentSpeed > 0.05 && totalDuration > currentTimeSec {
                            eta = (totalDuration - currentTimeSec) / currentSpeed
                        }
                        
                        let progressObj = FFmpegProgress(
                            frame: currentFrame,
                            fps: currentFps,
                            currentTimeSeconds: currentTimeSec,
                            totalTimeSeconds: totalDuration,
                            progressRatio: ratio,
                            speed: currentSpeed,
                            bitrate: currentBitrate,
                            etaSeconds: eta
                        )
                        onProgress?(progressObj)
                    default:
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Thread-safe synchronized helper
private final class SynchronizedValue<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    
    init(_ value: T) {
        self.value = value
    }
    
    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    
    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}
