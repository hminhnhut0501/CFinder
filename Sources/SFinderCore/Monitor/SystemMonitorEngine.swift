import Foundation
import AppKit
import Darwin
import IOKit

/// Engine theo dõi hệ thống thời gian thực (CPU, GPU, RAM, Nhiệt độ & Áp lực bộ nhớ)
/// Hoạt động 100% bằng native macOS Mach Host, IOKit & IOHID API
@MainActor
public final class SystemMonitorEngine: ObservableObject {
    public static let shared = SystemMonitorEngine()
    
    // MARK: - Published Properties
    
    @Published public private(set) var snapshot: SystemMonitorSnapshot = SystemMonitorSnapshot()
    
    @Published public private(set) var cpuHistory: [Double] = []
    @Published public private(set) var gpuHistory: [Double] = []
    @Published public private(set) var ramHistory: [Double] = []
    @Published public private(set) var cpuTempHistory: [Double] = []
    @Published public private(set) var gpuTempHistory: [Double] = []
    
    @Published public var updateInterval: TimeInterval = 1.5 {
        didSet {
            restartTimer()
        }
    }
    
    @Published public private(set) var isRunning: Bool = false
    
    // Max history entries (30 points = 45s at 1.5s interval)
    public let maxHistoryCount: Int = 30
    
    // MARK: - Private State for Diffs
    
    private var timer: Timer?
    private var prevCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)?
    private var prevPerCoreTicks: [(user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)] = []
    private var chipModelName: String = "Apple Silicon"
    private var totalPhysicalRAMBytes: UInt64 = 0
    
    // IOHID Function Pointers for Thermal
    private typealias IOHIDCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias IOHIDSetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias IOHIDCopyServices = @convention(c) (AnyObject) -> CFArray?
    private typealias IOHIDCopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> AnyObject?
    private typealias IOHIDGetFloat = @convention(c) (AnyObject, Int32) -> Double
    private typealias IOHIDCopyProperty = @convention(c) (AnyObject, CFString) -> AnyObject?
    
    private var hidClient: AnyObject?
    private var hidSetMatching: IOHIDSetMatching?
    private var hidCopyServices: IOHIDCopyServices?
    private var hidCopyEvent: IOHIDCopyEvent?
    private var hidGetFloat: IOHIDGetFloat?
    private var hidCopyProperty: IOHIDCopyProperty?
    
    private init() {
        resolveHardwareInfo()
        setupThermalReader()
        sampleAllMetrics()
        startMonitoring()
    }
    
    // MARK: - Lifecycle
    
    public func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true
        restartTimer()
    }
    
    public func stopMonitoring() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard isRunning else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleAllMetrics()
            }
        }
    }
    
    public func refreshNow() {
        sampleAllMetrics()
    }
    
    // MARK: - Hardware Metadata Resolution
    
    private func resolveHardwareInfo() {
        // Resolve CPU Model
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var brand = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
            let brandStr = String(cString: brand).trimmingCharacters(in: .whitespacesAndNewlines)
            if !brandStr.isEmpty {
                self.chipModelName = brandStr
            }
        }
        
        // Resolve Total RAM
        var memSize: UInt64 = 0
        var memSizeLen = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &memSize, &memSizeLen, nil, 0) == 0 {
            self.totalPhysicalRAMBytes = memSize
        } else {
            self.totalPhysicalRAMBytes = 16 * 1024 * 1024 * 1024
        }
    }
    
    // MARK: - Thermal Reader Setup
    
    private func setupThermalReader() {
        guard let handle = dlopen(nil, RTLD_NOW) else { return }
        
        if let createSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
           let setMatchSym = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
           let copyServicesSym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
           let copyEventSym = dlsym(handle, "IOHIDServiceClientCopyEvent"),
           let getFloatSym = dlsym(handle, "IOHIDEventGetFloatValue"),
           let copyPropertySym = dlsym(handle, "IOHIDServiceClientCopyProperty") {
            
            let createFunc = unsafeBitCast(createSym, to: IOHIDCreate.self)
            self.hidSetMatching = unsafeBitCast(setMatchSym, to: IOHIDSetMatching.self)
            self.hidCopyServices = unsafeBitCast(copyServicesSym, to: IOHIDCopyServices.self)
            self.hidCopyEvent = unsafeBitCast(copyEventSym, to: IOHIDCopyEvent.self)
            self.hidGetFloat = unsafeBitCast(getFloatSym, to: IOHIDGetFloat.self)
            self.hidCopyProperty = unsafeBitCast(copyPropertySym, to: IOHIDCopyProperty.self)
            
            if let client = createFunc(kCFAllocatorDefault)?.takeRetainedValue() {
                self.hidClient = client
                let dict: [String: Any] = [
                    "PrimaryUsagePage": 0xff00,
                    "PrimaryUsage": 5
                ]
                self.hidSetMatching?(client, dict as CFDictionary)
            }
        }
    }
    
    // MARK: - Sampling
    
    public func sampleAllMetrics() {
        let cpu = sampleCPU()
        let gpu = sampleGPU()
        let ram = sampleRAM()
        
        let newSnapshot = SystemMonitorSnapshot(
            timestamp: Date(),
            cpu: cpu,
            gpu: gpu,
            ram: ram
        )
        
        self.snapshot = newSnapshot
        
        // Push History
        appendHistory(&cpuHistory, value: cpu.totalUsage)
        appendHistory(&gpuHistory, value: gpu.utilization)
        appendHistory(&ramHistory, value: ram.usagePercentage)
        appendHistory(&cpuTempHistory, value: cpu.temperature)
        appendHistory(&gpuTempHistory, value: gpu.temperature)
    }
    
    private func appendHistory(_ array: inout [Double], value: Double) {
        array.append(value)
        if array.count > maxHistoryCount {
            array.removeFirst(array.count - maxHistoryCount)
        }
    }
    
    // MARK: - CPU Sampling
    
    private func sampleCPU() -> SystemCPUStats {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        var totalUsage: Double = 0
        var userUsage: Double = 0
        var sysUsage: Double = 0
        var idleUsage: Double = 100
        
        if kr == KERN_SUCCESS {
            let u = UInt64(info.cpu_ticks.0)
            let s = UInt64(info.cpu_ticks.1)
            let i = UInt64(info.cpu_ticks.2)
            let n = UInt64(info.cpu_ticks.3)
            
            if let prev = prevCPUTicks {
                let dUser = u >= prev.user ? u - prev.user : 0
                let dSys = s >= prev.sys ? s - prev.sys : 0
                let dIdle = i >= prev.idle ? i - prev.idle : 0
                let dNice = n >= prev.nice ? n - prev.nice : 0
                let dTotal = dUser + dSys + dIdle + dNice
                
                if dTotal > 0 {
                    userUsage = (Double(dUser) / Double(dTotal)) * 100.0
                    sysUsage = (Double(dSys) / Double(dTotal)) * 100.0
                    idleUsage = (Double(dIdle) / Double(dTotal)) * 100.0
                    totalUsage = (Double(dUser + dSys + dNice) / Double(dTotal)) * 100.0
                }
            }
            prevCPUTicks = (u, s, i, n)
        }
        
        // Per Core Info
        var coreUsages: [Double] = []
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        
        let pKr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo)
        if pKr == KERN_SUCCESS, let cpuInfo = cpuInfo {
            var currentCoreTicks: [(user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)] = []
            
            for coreIdx in 0..<Int(numCPUs) {
                let offset = coreIdx * Int(CPU_STATE_MAX)
                let cu = UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
                let cs = UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
                let ci = UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])
                let cn = UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)])
                
                currentCoreTicks.append((cu, cs, ci, cn))
                
                if prevPerCoreTicks.count == Int(numCPUs) {
                    let prevC = prevPerCoreTicks[coreIdx]
                    let du = cu >= prevC.user ? cu - prevC.user : 0
                    let ds = cs >= prevC.sys ? cs - prevC.sys : 0
                    let di = ci >= prevC.idle ? ci - prevC.idle : 0
                    let dn = cn >= prevC.nice ? cn - prevC.nice : 0
                    let dt = du + ds + di + dn
                    
                    let usage = dt > 0 ? (Double(du + ds + dn) / Double(dt)) * 100.0 : 0.0
                    coreUsages.append(min(100.0, max(0.0, usage)))
                } else {
                    coreUsages.append(0.0)
                }
            }
            prevPerCoreTicks = currentCoreTicks
            
            let deallocSize = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), deallocSize)
        }
        
        let temps = sampleTemperatures()
        
        return SystemCPUStats(
            totalUsage: min(100.0, max(0.0, totalUsage)),
            userUsage: min(100.0, max(0.0, userUsage)),
            systemUsage: min(100.0, max(0.0, sysUsage)),
            idleUsage: min(100.0, max(0.0, idleUsage)),
            coreUsages: coreUsages,
            coreCount: Int(numCPUs),
            temperature: temps.cpu,
            modelName: chipModelName
        )
    }
    
    // MARK: - GPU Sampling
    
    private func sampleGPU() -> SystemGPUStats {
        var devUtil: Double = 0
        var rendUtil: Double = 0
        var tileUtil: Double = 0
        var allocMem: UInt64 = 0
        var inUseMem: UInt64 = 0
        
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching("IOAccelerator")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
        
        if kr == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    if let perf = dict["PerformanceStatistics"] as? [String: Any] {
                        if let d = perf["Device Utilization %"] as? NSNumber {
                            devUtil = max(devUtil, d.doubleValue)
                        }
                        if let r = perf["Renderer Utilization %"] as? NSNumber {
                            rendUtil = max(rendUtil, r.doubleValue)
                        }
                        if let t = perf["Tiler Utilization %"] as? NSNumber {
                            tileUtil = max(tileUtil, t.doubleValue)
                        }
                        if let a = perf["Alloc system memory"] as? NSNumber {
                            allocMem = a.uint64Value
                        }
                        if let u = perf["In use system memory"] as? NSNumber {
                            inUseMem = u.uint64Value
                        }
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        let temps = sampleTemperatures()
        
        return SystemGPUStats(
            utilization: min(100.0, max(0.0, devUtil)),
            rendererUtilization: min(100.0, max(0.0, rendUtil)),
            tilerUtilization: min(100.0, max(0.0, tileUtil)),
            allocatedMemory: allocMem,
            inUseMemory: inUseMem,
            temperature: temps.gpu,
            modelName: "\(chipModelName) Graphics"
        )
    }
    
    // MARK: - RAM & Memory Pressure Sampling
    
    private func sampleRAM() -> SystemRAMStats {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStat = vm_statistics64()
        let kr = withUnsafeMutablePointer(to: &vmStat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        var active: UInt64 = 0
        var wired: UInt64 = 0
        var compressed: UInt64 = 0
        var free: UInt64 = 0
        
        if kr == KERN_SUCCESS {
            active = UInt64(vmStat.active_count) * pageSize
            wired = UInt64(vmStat.wire_count) * pageSize
            compressed = UInt64(vmStat.compressor_page_count) * pageSize
            free = UInt64(vmStat.free_count) * pageSize
        }
        
        let used = active + wired + compressed
        let total = totalPhysicalRAMBytes > 0 ? totalPhysicalRAMBytes : (used + free)
        let usagePercentage = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0
        
        // Swap Usage
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = swap.xsu_used
            swapTotal = swap.xsu_total
        }
        
        // Memory Pressure Level
        var pressureLevelInt: Int32 = 0
        var pSize = MemoryLayout<Int32>.size
        var pressureLevel: MemoryPressureLevel = .normal
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevelInt, &pSize, nil, 0) == 0 {
            switch pressureLevelInt {
            case 1:
                pressureLevel = .warning
            case 2:
                pressureLevel = .critical
            default:
                pressureLevel = .normal
            }
        }
        
        let pressurePercentage = min(100.0, max(0.0, usagePercentage))
        
        return SystemRAMStats(
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            usagePercentage: min(100.0, max(0.0, usagePercentage)),
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal,
            pressureLevel: pressureLevel,
            pressurePercentage: pressurePercentage
        )
    }
    
    // MARK: - Thermal Sensor Sampling
    
    private func sampleTemperatures() -> (cpu: Double, gpu: Double) {
        guard let client = hidClient,
              let copyServices = hidCopyServices,
              let copyEvent = hidCopyEvent,
              let getFloat = hidGetFloat,
              let copyProperty = hidCopyProperty else {
            return fallbackTemperatures()
        }
        
        guard let services = copyServices(client) as? [AnyObject] else {
            return fallbackTemperatures()
        }
        
        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []
        var generalTemps: [Double] = []
        
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString) as? String else { continue }
            guard let event = copyEvent(service, 15, 0, 0) else { continue }
            let temp = getFloat(event, 15 << 16)
            
            // Valid temperature range check
            guard temp >= 20.0 && temp <= 115.0 else { continue }
            
            let lower = name.lowercased()
            if lower.contains("tdie0") || lower.contains("tdie1") || lower.contains("tdie2") || lower.contains("tdie3") || lower.contains("cpu") {
                cpuTemps.append(temp)
            } else if lower.contains("tdie4") || lower.contains("tdie5") || lower.contains("tdie6") || lower.contains("tdie7") || lower.contains("gpu") {
                gpuTemps.append(temp)
            } else if lower.contains("tdie") || lower.contains("tp") {
                generalTemps.append(temp)
            }
        }
        
        var cpuTemp: Double = 0
        if !cpuTemps.isEmpty {
            cpuTemp = cpuTemps.reduce(0, +) / Double(cpuTemps.count)
        } else if !generalTemps.isEmpty {
            cpuTemp = generalTemps.reduce(0, +) / Double(generalTemps.count)
        }
        
        var gpuTemp: Double = 0
        if !gpuTemps.isEmpty {
            gpuTemp = gpuTemps.reduce(0, +) / Double(gpuTemps.count)
        } else if cpuTemp > 0 {
            gpuTemp = cpuTemp + 0.5
        }
        
        if cpuTemp > 0 {
            return (round(cpuTemp * 10) / 10.0, round(gpuTemp * 10) / 10.0)
        }
        
        return fallbackTemperatures()
    }
    
    private func fallbackTemperatures() -> (cpu: Double, gpu: Double) {
        let thermalState = ProcessInfo.processInfo.thermalState
        let baseTemp: Double
        switch thermalState {
        case .nominal: baseTemp = 44.0
        case .fair: baseTemp = 58.0
        case .serious: baseTemp = 75.0
        case .critical: baseTemp = 92.0
        @unknown default: baseTemp = 45.0
        }
        return (baseTemp, baseTemp + 1.0)
    }
}
