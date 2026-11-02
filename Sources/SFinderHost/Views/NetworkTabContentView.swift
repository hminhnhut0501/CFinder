import SwiftUI
import AppKit
import SFinderCore

public struct NetworkTabContentView: View {
    @ObservedObject private var monitor = NetworkMonitorEngine.shared
    @ObservedObject private var speedTester = SpeedTestEngine.shared
    
    @State private var showingHistory: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - 1. Top 4 Summary Metrics Bar
                summaryMetricsBar
                
                // MARK: - 2. Speed Test Hero Card
                speedTestCard
                
                // MARK: - 3. Live Realtime Throughput Card
                liveThroughputCard
                
                // MARK: - 4. Interface & Network Info Card
                networkInfoCard
                
                // MARK: - 5. Speed Test History Card (if records exist)
                if !speedTester.history.isEmpty {
                    speedTestHistoryCard
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.black.opacity(0.18))
    }
    
    // MARK: - Top Summary Metrics Bar
    
    private var compactPublicIP: String {
        guard let ip = monitor.interfaceInfo.publicIP else { return "Đang lấy..." }
        if ip.contains(":") && ip.count > 16 {
            let parts = ip.split(separator: ":")
            if parts.count >= 3 {
                return "\(parts[0]):\(parts[1]):...:\(parts.last!)"
            }
        }
        return ip
    }
    
    private var summaryMetricsBar: some View {
        let tp = monitor.throughput
        let ifInfo = monitor.interfaceInfo
        
        return HStack(spacing: 12) {
            summaryChip(
                title: "TẢI XUỐNG",
                value: tp.formattedDownloadSpeed,
                subtitle: "Đỉnh: \(tp.formattedPeakDownload)",
                icon: "arrow.down.circle.fill",
                accentColor: Color(hex: "0284C7")
            )
            
            summaryChip(
                title: "TẢI LÊN",
                value: tp.formattedUploadSpeed,
                subtitle: "Đỉnh: \(tp.formattedPeakUpload)",
                icon: "arrow.up.circle.fill",
                accentColor: Color(hex: "818CF8")
            )
            
            summaryChip(
                title: "IP CÔNG CỘNG",
                value: compactPublicIP,
                subtitle: ifInfo.countryCode != nil ? "\(ifInfo.countryCode!) • \(ifInfo.serverColo ?? "CDN")" : "Toàn cầu",
                icon: "globe.asia.australia.fill",
                accentColor: Color(hex: "10B981")
            )
            
            summaryChip(
                title: "TRẠNG THÁI",
                value: ifInfo.isConnected ? "Trực tuyến" : "Mất kết nối",
                subtitle: ifInfo.displayName,
                icon: ifInfo.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                accentColor: ifInfo.isConnected ? Color(hex: "10B981") : Color(hex: "EF4444")
            )
        }
    }
    
    private func summaryChip(title: String, value: String, subtitle: String, icon: String, accentColor: Color) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 34, height: 34)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Speed Test Card
    
    private var speedTestCard: some View {
        let isRunning = speedTester.phase.isRunning
        let phase = speedTester.phase
        let result = speedTester.lastResult
        
        return VStack(alignment: .leading, spacing: 16) {
            // Card Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "38BDF8"))
                    Text("ĐO TỐC ĐỘ INTERNET")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                if let last = result, !isRunning {
                    HStack(spacing: 6) {
                        Image(systemName: last.rating.icon)
                            .font(.system(size: 10))
                        Text(last.rating.title)
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundColor(ratingColor(last.rating))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ratingColor(last.rating).opacity(0.12)))
                }
            }
            
            // Speed Gauge & Sub-metrics Row
            HStack(spacing: 32) {
                // Big Circular Speedometer
                speedometerGauge
                    .frame(width: 170, height: 140)
                
                // 3 Core Metric Displays
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        speedMetricBlock(
                            title: "ĐỘ TRỄ (PING)",
                            value: String(format: "%.0f", isRunning ? speedTester.livePingMs : (result?.pingMs ?? 0)),
                            unit: "ms",
                            subText: isRunning ? "Đang đo..." : "Dao động: \(String(format: "%.1f", result?.jitterMs ?? 0)) ms",
                            icon: "bolt.horizontal.fill",
                            color: Color(hex: "F59E0B")
                        )
                        
                        speedMetricBlock(
                            title: "TẢI XUỐNG",
                            value: String(format: "%.1f", isRunning ? speedTester.liveDownloadMbps : (result?.downloadMbps ?? 0)),
                            unit: "Mbps",
                            subText: isRunning ? "Đang tải dữ liệu..." : "Tương đương \(String(format: "%.1f", (result?.downloadMbps ?? 0) / 8.0)) MB/s",
                            icon: "arrow.down.circle.fill",
                            color: Color(hex: "0284C7")
                        )
                        
                        speedMetricBlock(
                            title: "TẢI LÊN",
                            value: String(format: "%.1f", isRunning ? speedTester.liveUploadMbps : (result?.uploadMbps ?? 0)),
                            unit: "Mbps",
                            subText: isRunning ? "Đang gửi dữ liệu..." : "Tương đương \(String(format: "%.1f", (result?.uploadMbps ?? 0) / 8.0)) MB/s",
                            icon: "arrow.up.circle.fill",
                            color: Color(hex: "818CF8")
                        )
                    }
                    
                    // Status & Button row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase.statusText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                            
                            if let last = result, !isRunning {
                                Text(last.rating.description)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                        }
                        
                        Spacer()
                        
                        if isRunning {
                            Button(action: {
                                speedTester.cancelTest()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Huỷ đo")
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.red.opacity(0.2)))
                                .overlay(Capsule().stroke(Color.red.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            Button(action: {
                                speedTester.startTest()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10))
                                    Text("Bắt đầu đo tốc độ")
                                }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "0284C7"), Color(hex: "0369A1")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Capsule())
                                .shadow(color: Color(hex: "0284C7").opacity(0.35), radius: 6, x: 0, y: 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private var speedometerGauge: some View {
        let isRunning = speedTester.phase.isRunning
        let speed = isRunning ? speedTester.currentGaugeSpeed : (speedTester.lastResult?.downloadMbps ?? 0)
        let maxDisplaySpeed: Double = 300.0
        let fraction = min(1.0, max(0.0, speed / maxDisplaySpeed))
        
        return ZStack {
            // Track Arc
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(
                    Color.white.opacity(0.06),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
            
            // Value Arc
            Circle()
                .trim(from: 0.15, to: 0.15 + (fraction * 0.70))
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "0284C7"), Color(hex: "38BDF8"), Color(hex: "818CF8")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.25), value: fraction)
            
            // Center Readout
            VStack(spacing: 2) {
                Text(String(format: "%.1f", speed))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(isRunning ? "Mbps Live" : "Mbps Đỉnh")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(Color(hex: "38BDF8"))
            }
        }
    }
    
    private func speedMetricBlock(title: String, value: String, unit: String, subText: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            
            Text(subText)
                .font(.system(size: 8.5))
                .foregroundColor(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Live Realtime Throughput Card
    
    private var liveThroughputCard: some View {
        let tp = monitor.throughput
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "0284C7"))
                    Text("LƯU LƯỢNG MẠNG THỜI GIAN THỰC")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: "0284C7")).frame(width: 6, height: 6)
                        Text("Tải xuống: \(tp.formattedDownloadSpeed)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: "818CF8")).frame(width: 6, height: 6)
                        Text("Tải lên: \(tp.formattedUploadSpeed)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            // Dual Sparklines
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.25))
                    
                    // Grid lines
                    VStack {
                        Divider().background(Color.white.opacity(0.03))
                        Spacer()
                        Divider().background(Color.white.opacity(0.03))
                        Spacer()
                        Divider().background(Color.white.opacity(0.03))
                    }
                    .padding(.vertical, 6)
                    
                    let chartW = max(10, geo.size.width - 16)
                    let chartH = max(10, geo.size.height - 16)
                    
                    // Download Sparkline (Cyan/Blue)
                    sparklinePath(
                        data: monitor.downloadHistory,
                        maxVal: max(100_000, monitor.downloadHistory.max() ?? 100_000),
                        width: chartW,
                        height: chartH
                    )
                    .stroke(
                        Color(hex: "0284C7"),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    
                    // Upload Sparkline (Purple)
                    sparklinePath(
                        data: monitor.uploadHistory,
                        maxVal: max(100_000, monitor.downloadHistory.max() ?? 100_000),
                        width: chartW,
                        height: chartH
                    )
                    .stroke(
                        Color(hex: "818CF8"),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
            .frame(height: 75)
            
            // Session Volume Footer
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Text("Tổng phiên tải về:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                    Text(tp.formattedTotalDownloaded)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "38BDF8"))
                }
                
                HStack(spacing: 6) {
                    Text("Tổng phiên gửi đi:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                    Text(tp.formattedTotalUploaded)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "818CF8"))
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    ForEach([1.0, 2.0, 5.0], id: \.self) { sec in
                        Button(action: {
                            monitor.sampleInterval = sec
                        }) {
                            Text("\(String(format: "%.0f", sec))s")
                                .font(.system(size: 9.5, weight: monitor.sampleInterval == sec ? .bold : .medium))
                                .foregroundColor(monitor.sampleInterval == sec ? .white : .white.opacity(0.4))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule().fill(monitor.sampleInterval == sec ? Color(hex: "0284C7") : Color.white.opacity(0.04))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Interface & Network Info Card
    
    private var networkInfoCard: some View {
        let info = monitor.interfaceInfo
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(hex: "10B981"))
                    Text("THÔNG TIN GIAO DIỆN & ĐỊA CHỈ IP")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                Button(action: {
                    monitor.refreshLocalInterfaces()
                    Task {
                        await monitor.fetchPublicIPInfo(force: true)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9.5))
                        Text("Làm mới")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                infoCell(label: "Giao diện chính", value: info.displayName, icon: info.interfaceType.icon)
                infoCell(label: "Địa chỉ IP nội bộ (LAN)", value: info.localIPv4 ?? "---", icon: "laptopcomputer")
                infoCell(label: "Địa chỉ MAC phần cứng", value: info.macAddress ?? "---", icon: "barcode")
                infoCell(label: "Địa chỉ IP công cộng (WAN)", value: info.publicIP ?? "---", icon: "globe")
                infoCell(label: "Máy chủ định tuyến (PoP)", value: info.serverColo ?? "Cloudflare CDN", icon: "server.rack")
                infoCell(label: "Khu vực / Quốc gia", value: info.countryCode ?? "Toàn cầu", icon: "mappin.and.ellipse")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private func infoCell(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 18)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.015)))
    }
    
    // MARK: - Speed Test History Card
    
    private var speedTestHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                    Text("LỊCH SỬ CÁC LẦN ĐO GẦN ĐÂY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                Button(action: {
                    speedTester.clearHistory()
                }) {
                    Text("Xoá lịch sử")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.red.opacity(0.75))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            VStack(spacing: 6) {
                ForEach(Array(speedTester.history.prefix(5))) { item in
                    HStack(spacing: 12) {
                        Text(item.formattedDate)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 80, alignment: .leading)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color(hex: "F59E0B"))
                            Text(item.formattedPing)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(width: 60, alignment: .leading)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color(hex: "0284C7"))
                            Text(item.formattedDownload)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(width: 85, alignment: .leading)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color(hex: "818CF8"))
                            Text(item.formattedUpload)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(width: 85, alignment: .leading)
                        
                        Spacer()
                        
                        Text(item.rating.title)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ratingColor(item.rating))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(ratingColor(item.rating).opacity(0.12)))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.015)))
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Helper Views & Functions
    
    private func sparklinePath(data: [Double], maxVal: Double, width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            guard data.count > 1 else { return }
            let safeMax = max(1.0, maxVal)
            
            for (idx, val) in data.enumerated() {
                let xRatio = CGFloat(idx) / CGFloat(max(1, data.count - 1))
                let yRatio = 1.0 - CGFloat(min(1.0, max(0.0, val / safeMax)))
                
                let pt = CGPoint(x: xRatio * width, y: yRatio * height)
                if idx == 0 {
                    path.move(to: pt)
                } else {
                    path.addLine(to: pt)
                }
            }
        }
    }
    
    private func ratingColor(_ rating: NetworkQualityRating) -> Color {
        switch rating {
        case .ultra: return Color(hex: "10B981")
        case .fast: return Color(hex: "0284C7")
        case .moderate: return Color(hex: "F59E0B")
        case .slow: return Color(hex: "EF4444")
        }
    }
}
