import Foundation
import OSLog

/// Monitors system resources and adjusts worker concurrency.
public actor ResourceController {
    public enum Profile: String, Sendable {
        case eco        // Minimal resource use
        case balanced   // Default
        case maximum    // All cores
    }

    public private(set) var profile: Profile = .balanced
    private let logger = Logger(subsystem: "com.sfinder.videotwin", category: "resource")

    public init(profile: Profile = .balanced) {
        self.profile = profile
    }

    /// Returns recommended decode worker count for current profile and thermal state.
    public func recommendedDecodeWorkers() -> Int {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let base: Int
        switch profile {
        case .eco: base = max(1, cores / 4)
        case .balanced: base = max(2, cores / 2)
        case .maximum: base = cores
        }
        let memBytes = ProcessInfo.processInfo.physicalMemory
        let memoryLimit: Int
        if memBytes < 8 * 1024 * 1024 * 1024 {
            memoryLimit = 2
        } else if memBytes < 16 * 1024 * 1024 * 1024 {
            memoryLimit = 4
        } else {
            memoryLimit = 8
        }
        let thermalLimit: Int
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalLimit = 8
        case .fair: thermalLimit = 4
        case .serious, .critical: thermalLimit = 1
        @unknown default: thermalLimit = 2
        }
        return max(1, min(base, memoryLimit, thermalLimit))
    }

    public func recommendedFingerprintWorkers() -> Int { recommendedDecodeWorkers() }

    public func setProfile(_ p: Profile) {
        profile = p
        logger.info("Resource profile changed to \(p.rawValue)")
    }
}
