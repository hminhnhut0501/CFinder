import Foundation
import Network
import Combine
import Darwin

/// Engine theo dõi trạng thái và tốc độ mạng thời gian thực
/// Hoạt động 100% Native bằng Darwin sysctl, getifaddrs và Network.framework
@MainActor
public final class NetworkMonitorEngine: ObservableObject {
    public static let shared = NetworkMonitorEngine()
    
    // MARK: - Published Properties
    
    @Published public private(set) var throughput: NetworkThroughputStats = NetworkThroughputStats()
    @Published public private(set) var interfaceInfo: NetworkInterfaceInfo = NetworkInterfaceInfo()
    
    @Published public private(set) var downloadHistory: [Double] = []
    @Published public private(set) var uploadHistory: [Double] = []
    
    @Published public private(set) var isMonitoring: Bool = false
    @Published public var sampleInterval: TimeInterval = 1.0 {
        didSet {
            restartTimer()
        }
    }
    
    public let maxHistoryCount: Int = 30
    
    // MARK: - Private State
    
    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.sfinder.network.pathmonitor")
    
    private var previousBytesIn: UInt64 = 0
    private var previousBytesOut: UInt64 = 0
    private var previousTimestamp: Date = Date()
    private var baselineBytesIn: UInt64 = 0
    private var baselineBytesOut: UInt64 = 0
    private var hasBaseline: Bool = false
    
    private var isFetchingPublicIP: Bool = false
    private var lastPublicIPFetchTime: Date?
    
    private init() {
        setupPathMonitor()
        refreshLocalInterfaces()
        sampleThroughput()
        startMonitoring()
        
        Task {
            await fetchPublicIPInfo()
        }
    }
    
    // MARK: - Monitoring Controls
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        let (currentIn, currentOut) = Self.readRawNetworkBytes()
        if !hasBaseline {
            baselineBytesIn = currentIn
            baselineBytesOut = currentOut
            hasBaseline = true
        }
        previousBytesIn = currentIn
        previousBytesOut = currentOut
        previousTimestamp = Date()
        
        restartTimer()
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }
    
    private func restartTimer() {
        timer?.invalidate()
        guard isMonitoring else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleThroughput()
            }
        }
    }
    
    // MARK: - Periodic Sampling
    
    public func sampleThroughput() {
        let now = Date()
        let elapsed = max(0.2, now.timeIntervalSince(previousTimestamp))
        let (currentIn, currentOut) = Self.readRawNetworkBytes()
        
        let deltaIn = currentIn >= previousBytesIn ? currentIn - previousBytesIn : 0
        let deltaOut = currentOut >= previousBytesOut ? currentOut - previousBytesOut : 0
        
        previousBytesIn = currentIn
        previousBytesOut = currentOut
        previousTimestamp = now
        
        let inSpeed = Double(deltaIn) / elapsed
        let outSpeed = Double(deltaOut) / elapsed
        
        let sessionTotalIn = currentIn >= baselineBytesIn ? currentIn - baselineBytesIn : 0
        let sessionTotalOut = currentOut >= baselineBytesOut ? currentOut - baselineBytesOut : 0
        
        let newPeakDown = max(throughput.peakDownloadBytesPerSec, inSpeed)
        let newPeakUp = max(throughput.peakUploadBytesPerSec, outSpeed)
        
        self.throughput = NetworkThroughputStats(
            downloadBytesPerSec: inSpeed,
            uploadBytesPerSec: outSpeed,
            peakDownloadBytesPerSec: newPeakDown,
            peakUploadBytesPerSec: newPeakUp,
            totalDownloadedBytes: sessionTotalIn,
            totalUploadedBytes: sessionTotalOut
        )
        
        // Append history
        downloadHistory.append(inSpeed)
        if downloadHistory.count > maxHistoryCount {
            downloadHistory.removeFirst(downloadHistory.count - maxHistoryCount)
        }
        
        uploadHistory.append(outSpeed)
        if uploadHistory.count > maxHistoryCount {
            uploadHistory.removeFirst(uploadHistory.count - maxHistoryCount)
        }
    }
    
    // MARK: - NWPathMonitor Connectivity
    
    private func setupPathMonitor() {
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor
        
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let isConnected = (path.status == .satisfied)
                
                var ifType: NetworkInterfaceType = .other
                if path.usesInterfaceType(.wifi) {
                    ifType = .wifi
                } else if path.usesInterfaceType(.wiredEthernet) {
                    ifType = .ethernet
                } else if path.usesInterfaceType(.cellular) {
                    ifType = .cellular
                } else if path.usesInterfaceType(.loopback) {
                    ifType = .loopback
                }
                
                self.interfaceInfo.isConnected = isConnected
                self.interfaceInfo.interfaceType = ifType
                self.refreshLocalInterfaces()
            }
        }
        monitor.start(queue: pathMonitorQueue)
    }
    
    // MARK: - Local Interface Resolution
    
    public func refreshLocalInterfaces() {
        var activeName = "en0"
        var localIPv4: String? = nil
        var localIPv6: String? = nil
        var macAddress: String? = nil
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & (IFF_UP | IFF_RUNNING)) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            
            let name = String(cString: ptr.pointee.ifa_name)
            let family = ptr.pointee.ifa_addr.pointee.sa_family
            
            if family == UInt8(AF_INET) && localIPv4 == nil {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var ifaAddr = ptr.pointee.ifa_addr.pointee
                getnameinfo(&ifaAddr, socklen_t(ifaAddr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                localIPv4 = String(cString: hostname)
                activeName = name
            } else if family == UInt8(AF_INET6) && localIPv6 == nil {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var ifaAddr = ptr.pointee.ifa_addr.pointee
                getnameinfo(&ifaAddr, socklen_t(ifaAddr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ip6 = String(cString: hostname)
                if !ip6.hasPrefix("fe80") { // Prefer global unicast
                    localIPv6 = ip6
                }
            } else if family == UInt8(AF_LINK) && name == activeName && macAddress == nil {
                let sdl = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                let nlen = Int(sdl.sdl_nlen)
                let alen = Int(sdl.sdl_alen)
                if alen == 6 {
                    let bytes = withUnsafeBytes(of: sdl.sdl_data) { bufPtr -> [UInt8] in
                        let base = bufPtr.baseAddress!.advanced(by: nlen)
                        return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: alen))
                    }
                    macAddress = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
                }
            }
        }
        
        self.interfaceInfo.name = activeName
        self.interfaceInfo.localIPv4 = localIPv4
        self.interfaceInfo.localIPv6 = localIPv6
        self.interfaceInfo.macAddress = macAddress
        self.interfaceInfo.displayName = "\(self.interfaceInfo.interfaceType.title) (\(activeName))"
    }
    
    // MARK: - Public IP & Location Resolver
    
    public func fetchPublicIPInfo(force: Bool = false) async {
        if isFetchingPublicIP && !force { return }
        if let last = lastPublicIPFetchTime, !force, Date().timeIntervalSince(last) < 120 { return }
        
        isFetchingPublicIP = true
        defer { isFetchingPublicIP = false }
        
        guard let url = URL(string: "https://speed.cloudflare.com/cdn-cgi/trace") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else {
                return
            }
            
            var parsedIP: String?
            var parsedLoc: String?
            var parsedColo: String?
            
            for line in text.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: "=")
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let val = parts[1].trimmingCharacters(in: .whitespaces)
                    if key == "ip" { parsedIP = val }
                    else if key == "loc" { parsedLoc = val }
                    else if key == "colo" { parsedColo = val }
                }
            }
            
            self.interfaceInfo.publicIP = parsedIP
            self.interfaceInfo.countryCode = parsedLoc
            self.interfaceInfo.serverColo = parsedColo
            self.lastPublicIPFetchTime = Date()
        } catch {
            // Keep existing public IP or fallback
        }
    }
    
    // MARK: - Native Darwin Raw Bytes Reader
    
    public static func readRawNetworkBytes() -> (inBytes: UInt64, outBytes: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        if sysctl(&mib, 6, nil, &len, nil, 0) < 0 { return (0, 0) }
        
        var buffer = [UInt8](repeating: 0, count: len)
        if sysctl(&mib, 6, &buffer, &len, nil, 0) < 0 { return (0, 0) }
        
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var offset = 0
        
        while offset < len {
            let msgPtr = buffer.withUnsafeBytes { $0.baseAddress!.advanced(by: offset) }
            let ifm = msgPtr.assumingMemoryBound(to: if_msghdr2.self).pointee
            offset += Int(ifm.ifm_msglen)
            
            if ifm.ifm_type == RTM_IFINFO2 {
                let sdlPtr = msgPtr.advanced(by: MemoryLayout<if_msghdr2>.size).assumingMemoryBound(to: sockaddr_dl.self).pointee
                let n = Int(sdlPtr.sdl_nlen)
                if n > 0 {
                    let namePtr = msgPtr.advanced(by: MemoryLayout<if_msghdr2>.size + MemoryLayout<sockaddr_dl>.size - 12)
                    let nameBytes = [UInt8](UnsafeBufferPointer(start: namePtr.assumingMemoryBound(to: UInt8.self), count: n))
                    let name = String(bytes: nameBytes, encoding: .utf8) ?? ""
                    if !name.hasPrefix("lo") {
                        totalIn += ifm.ifm_data.ifi_ibytes
                        totalOut += ifm.ifm_data.ifi_obytes
                    }
                }
            }
        }
        return (totalIn, totalOut)
    }
}
