import Foundation

public enum MemoryPressureLevel: String, CaseIterable, Sendable {
    case normal = "normal"
    case warning = "warning"
    case critical = "critical"
    
    public var title: String {
        switch self {
        case .normal: return "Bình thường"
        case .warning: return "Cảnh báo"
        case .critical: return "Nguy kịch"
        }
    }
    
    public var statusDescription: String {
        switch self {
        case .normal: return "Bộ nhớ khả dụng tốt, không nén swap"
        case .warning: return "Bộ nhớ bắt đầu nén, tải trung bình"
        case .critical: return "Bộ nhớ đầy nghiêm trọng, đang swap nhiều"
        }
    }
}

public struct SystemCPUStats: Equatable, Sendable {
    public var totalUsage: Double
    public var userUsage: Double
    public var systemUsage: Double
    public var idleUsage: Double
    public var coreUsages: [Double]
    public var coreCount: Int
    public var temperature: Double
    public var modelName: String
    
    public init(
        totalUsage: Double = 0,
        userUsage: Double = 0,
        systemUsage: Double = 0,
        idleUsage: Double = 100,
        coreUsages: [Double] = [],
        coreCount: Int = 0,
        temperature: Double = 0,
        modelName: String = "Apple Silicon"
    ) {
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.idleUsage = idleUsage
        self.coreUsages = coreUsages
        self.coreCount = coreCount
        self.temperature = temperature
        self.modelName = modelName
    }
}

public struct SystemGPUStats: Equatable, Sendable {
    public var utilization: Double
    public var rendererUtilization: Double
    public var tilerUtilization: Double
    public var allocatedMemory: UInt64
    public var inUseMemory: UInt64
    public var temperature: Double
    public var modelName: String
    
    public init(
        utilization: Double = 0,
        rendererUtilization: Double = 0,
        tilerUtilization: Double = 0,
        allocatedMemory: UInt64 = 0,
        inUseMemory: UInt64 = 0,
        temperature: Double = 0,
        modelName: String = "Apple GPU"
    ) {
        self.utilization = utilization
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.allocatedMemory = allocatedMemory
        self.inUseMemory = inUseMemory
        self.temperature = temperature
        self.modelName = modelName
    }
}

public struct SystemRAMStats: Equatable, Sendable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var freeBytes: UInt64
    public var activeBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var usagePercentage: Double
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var pressureLevel: MemoryPressureLevel
    public var pressurePercentage: Double
    
    public init(
        totalBytes: UInt64 = 0,
        usedBytes: UInt64 = 0,
        freeBytes: UInt64 = 0,
        activeBytes: UInt64 = 0,
        wiredBytes: UInt64 = 0,
        compressedBytes: UInt64 = 0,
        usagePercentage: Double = 0,
        swapUsedBytes: UInt64 = 0,
        swapTotalBytes: UInt64 = 0,
        pressureLevel: MemoryPressureLevel = .normal,
        pressurePercentage: Double = 0
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.usagePercentage = usagePercentage
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressureLevel = pressureLevel
        self.pressurePercentage = pressurePercentage
    }
    
    public var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .memory)
    }
    
    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .memory)
    }
    
    public var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: Int64(freeBytes), countStyle: .memory)
    }
    
    public var formattedSwapUsed: String {
        ByteCountFormatter.string(fromByteCount: Int64(swapUsedBytes), countStyle: .memory)
    }
    
    public var formattedSwapTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(swapTotalBytes), countStyle: .memory)
    }
}

public struct SystemMonitorSnapshot: Equatable, Sendable {
    public var timestamp: Date
    public var cpu: SystemCPUStats
    public var gpu: SystemGPUStats
    public var ram: SystemRAMStats
    
    public init(
        timestamp: Date = Date(),
        cpu: SystemCPUStats = SystemCPUStats(),
        gpu: SystemGPUStats = SystemGPUStats(),
        ram: SystemRAMStats = SystemRAMStats()
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.ram = ram
    }
}
