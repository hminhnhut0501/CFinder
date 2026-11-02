import Foundation
import SwiftUI

// MARK: - Network Interface Types

public enum NetworkInterfaceType: String, CaseIterable, Sendable, Codable {
    case wifi = "wifi"
    case ethernet = "ethernet"
    case cellular = "cellular"
    case loopback = "loopback"
    case other = "other"
    
    public var title: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet (Dây)"
        case .cellular: return "Mạng di động"
        case .loopback: return "Loopback"
        case .other: return "Mạng khác"
        }
    }
    
    public var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .other: return "network"
        }
    }
}

// MARK: - Network Interface Information

public struct NetworkInterfaceInfo: Equatable, Sendable {
    public var name: String
    public var displayName: String
    public var interfaceType: NetworkInterfaceType
    public var localIPv4: String?
    public var localIPv6: String?
    public var macAddress: String?
    public var gatewayIP: String?
    public var dnsServers: [String]
    public var publicIP: String?
    public var countryCode: String?
    public var serverColo: String?
    public var isConnected: Bool
    
    public init(
        name: String = "en0",
        displayName: String = "Wi-Fi (en0)",
        interfaceType: NetworkInterfaceType = .wifi,
        localIPv4: String? = nil,
        localIPv6: String? = nil,
        macAddress: String? = nil,
        gatewayIP: String? = nil,
        dnsServers: [String] = [],
        publicIP: String? = nil,
        countryCode: String? = nil,
        serverColo: String? = nil,
        isConnected: Bool = false
    ) {
        self.name = name
        self.displayName = displayName
        self.interfaceType = interfaceType
        self.localIPv4 = localIPv4
        self.localIPv6 = localIPv6
        self.macAddress = macAddress
        self.gatewayIP = gatewayIP
        self.dnsServers = dnsServers
        self.publicIP = publicIP
        self.countryCode = countryCode
        self.serverColo = serverColo
        self.isConnected = isConnected
    }
}

// MARK: - Live Throughput Stats

public struct NetworkThroughputStats: Equatable, Sendable {
    public var downloadBytesPerSec: Double
    public var uploadBytesPerSec: Double
    public var peakDownloadBytesPerSec: Double
    public var peakUploadBytesPerSec: Double
    public var totalDownloadedBytes: UInt64
    public var totalUploadedBytes: UInt64
    
    public init(
        downloadBytesPerSec: Double = 0,
        uploadBytesPerSec: Double = 0,
        peakDownloadBytesPerSec: Double = 0,
        peakUploadBytesPerSec: Double = 0,
        totalDownloadedBytes: UInt64 = 0,
        totalUploadedBytes: UInt64 = 0
    ) {
        self.downloadBytesPerSec = downloadBytesPerSec
        self.uploadBytesPerSec = uploadBytesPerSec
        self.peakDownloadBytesPerSec = peakDownloadBytesPerSec
        self.peakUploadBytesPerSec = peakUploadBytesPerSec
        self.totalDownloadedBytes = totalDownloadedBytes
        self.totalUploadedBytes = totalUploadedBytes
    }
    
    public var formattedDownloadSpeed: String {
        Self.formatSpeed(downloadBytesPerSec)
    }
    
    public var formattedUploadSpeed: String {
        Self.formatSpeed(uploadBytesPerSec)
    }
    
    public var formattedPeakDownload: String {
        Self.formatSpeed(peakDownloadBytesPerSec)
    }
    
    public var formattedPeakUpload: String {
        Self.formatSpeed(peakUploadBytesPerSec)
    }
    
    public var formattedTotalDownloaded: String {
        Self.formatBytes(totalDownloadedBytes)
    }
    
    public var formattedTotalUploaded: String {
        Self.formatBytes(totalUploadedBytes)
    }
    
    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB/s", bytesPerSec / (1024 * 1024 * 1024))
        } else if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }
    
    public static func formatBytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", b / (1024 * 1024 * 1024))
        } else if b >= 1024 * 1024 {
            return String(format: "%.1f MB", b / (1024 * 1024))
        } else if b >= 1024 {
            return String(format: "%.0f KB", b / 1024)
        } else {
            return "\(bytes) B"
        }
    }
}

// MARK: - Quality Rating

public enum NetworkQualityRating: String, CaseIterable, Sendable, Codable {
    case ultra = "ultra"
    case fast = "fast"
    case moderate = "moderate"
    case slow = "slow"
    
    public var title: String {
        switch self {
        case .ultra: return "Tuyệt đỉnh"
        case .fast: return "Rất nhanh"
        case .moderate: return "Trung bình"
        case .slow: return "Chậm"
        }
    }
    
    public var description: String {
        switch self {
        case .ultra: return "Tối ưu cho xem phim 4K/8K, Cloud Gaming và Livestream độ trễ thấp"
        case .fast: return "Đáp ứng tốt hội họp HD, gọi video nhiều người và tải tệp lớn mượt mà"
        case .moderate: return "Đủ cho lướt web, mạng xã hội, nghe nhạc và xem video chất lượng chuẩn"
        case .slow: return "Tốc độ còn hạn chế, có thể bị giật lag khi xem video hoặc gọi thoại"
        }
    }
    
    public var icon: String {
        switch self {
        case .ultra: return "bolt.shield.fill"
        case .fast: return "checkmark.seal.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .slow: return "wifi.exclamationmark"
        }
    }
    
    public static func evaluate(downloadMbps: Double, pingMs: Double) -> NetworkQualityRating {
        if downloadMbps >= 100.0 && pingMs <= 30.0 {
            return .ultra
        } else if downloadMbps >= 30.0 && pingMs <= 60.0 {
            return .fast
        } else if downloadMbps >= 10.0 {
            return .moderate
        } else {
            return .slow
        }
    }
}

// MARK: - Speed Test Result Record

public struct SpeedTestResult: Identifiable, Equatable, Sendable, Codable {
    public var id: UUID
    public var date: Date
    public var pingMs: Double
    public var jitterMs: Double
    public var downloadMbps: Double
    public var uploadMbps: Double
    public var serverLocation: String
    public var clientIP: String
    public var rating: NetworkQualityRating
    
    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        pingMs: Double = 0,
        jitterMs: Double = 0,
        downloadMbps: Double = 0,
        uploadMbps: Double = 0,
        serverLocation: String = "Cloudflare CDN",
        clientIP: String = "---",
        rating: NetworkQualityRating = .fast
    ) {
        self.id = id
        self.date = date
        self.pingMs = pingMs
        self.jitterMs = jitterMs
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.serverLocation = serverLocation
        self.clientIP = clientIP
        self.rating = rating
    }
    
    public var formattedDownload: String {
        String(format: "%.1f Mbps", downloadMbps)
    }
    
    public var formattedUpload: String {
        String(format: "%.1f Mbps", uploadMbps)
    }
    
    public var formattedPing: String {
        String(format: "%.0f ms", pingMs)
    }
    
    public var formattedJitter: String {
        String(format: "%.1f ms", jitterMs)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm dd/MM"
        return formatter.string(from: date)
    }
}

// MARK: - Speed Test Phase

public enum SpeedTestPhase: Equatable {
    case idle
    case preparing
    case pinging(progress: Double, currentPingMs: Double)
    case downloading(progress: Double, currentMbps: Double)
    case uploading(progress: Double, currentMbps: Double)
    case completed(SpeedTestResult)
    case failed(String)
    
    public var isRunning: Bool {
        switch self {
        case .preparing, .pinging, .downloading, .uploading:
            return true
        default:
            return false
        }
    }
    
    public var statusText: String {
        switch self {
        case .idle:
            return "Sẵn sàng kiểm tra tốc độ"
        case .preparing:
            return "Đang kết nối máy chủ CDN..."
        case .pinging(_, let ping):
            return "Đang đo độ trễ: \(String(format: "%.0f", ping)) ms"
        case .downloading(_, let speed):
            return "Đang đo tải xuống: \(String(format: "%.1f", speed)) Mbps"
        case .uploading(_, let speed):
            return "Đang đo tải lên: \(String(format: "%.1f", speed)) Mbps"
        case .completed:
            return "Đã hoàn thành đo tốc độ"
        case .failed(let err):
            return "Lỗi kiểm tra: \(err)"
        }
    }
}
