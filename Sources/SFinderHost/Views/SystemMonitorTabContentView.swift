import SwiftUI
import AppKit
import SFinderCore

public struct SystemMonitorTabContentView: View {
    @ObservedObject private var engine = SystemMonitorEngine.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            topSummaryBar
            
            cpuCard
            
            gpuCard
            
            ramAndPressureCard
            
            controlsBar
        }
    }
    
    // MARK: - Top Summary Bar (4 High-level Chips)
    
    private var topSummaryBar: some View {
        let snap = engine.snapshot
        return HStack(spacing: 12) {
            summaryChip(
                title: "CPU",
                value: "\(Int(snap.cpu.totalUsage))%",
                subtitle: "\(String(format: "%.1f", snap.cpu.temperature))°C",
                icon: "cpu",
                accentColor: Color.cyan
            )
            
            summaryChip(
                title: "GPU",
                value: "\(Int(snap.gpu.utilization))%",
                subtitle: "\(String(format: "%.1f", snap.gpu.temperature))°C",
                icon: "display",
                accentColor: Color(hex: "38BDF8")
            )
            
            summaryChip(
                title: "RAM",
                value: "\(Int(snap.ram.usagePercentage))%",
                subtitle: snap.ram.formattedUsed,
                icon: "memorychip",
                accentColor: Color(hex: "A855F7")
            )
            
            summaryChip(
                title: "ÁP LỰC",
                value: snap.ram.pressureLevel.title,
                subtitle: "\(Int(snap.ram.pressurePercentage))%",
                icon: "gauge.medium",
                accentColor: pressureColor(snap.ram.pressureLevel)
            )
        }
    }
    
    private func summaryChip(title: String, value: String, subtitle: String, icon: String, accentColor: Color) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - CPU Section
    
    private var cpuCard: some View {
        let snap = engine.snapshot
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.cyan)
                    Text("BỘ XỬ LÝ (CPU)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text(snap.cpu.modelName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                    
                    Text("\(String(format: "%.1f", snap.cpu.temperature))°C")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(tempColor(snap.cpu.temperature))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(tempColor(snap.cpu.temperature).opacity(0.12)))
                }
            }
            
            HStack(spacing: 20) {
                // Ring Gauge
                circularGauge(
                    percentage: snap.cpu.totalUsage,
                    color: .cyan,
                    label: "\(Int(snap.cpu.totalUsage))%",
                    caption: "Tổng tải"
                )
                .frame(width: 90, height: 90)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        statRow(label: "User:", value: "\(String(format: "%.1f", snap.cpu.userUsage))%", color: .white)
                        statRow(label: "System:", value: "\(String(format: "%.1f", snap.cpu.systemUsage))%", color: .cyan)
                        statRow(label: "Idle:", value: "\(String(format: "%.1f", snap.cpu.idleUsage))%", color: .white.opacity(0.4))
                    }
                    
                    // Sparkline
                    sparklineView(data: engine.cpuHistory, color: .cyan)
                        .frame(height: 38)
                }
            }
            
            // Per Core Grid
            if !snap.cpu.coreUsages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TẢI CHI TIẾT TỪNG NHÂN (\(snap.cpu.coreCount) CORES)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                    
                    coreUsageMatrix(usages: snap.cpu.coreUsages)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
    
    private func coreUsageMatrix(usages: [Double]) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(usages.count, 6))
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<usages.count, id: \.self) { idx in
                let val = usages[idx]
                VStack(spacing: 3) {
                    HStack {
                        Text("C\(idx)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text("\(Int(val))%")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(val > 80 ? Color.red : (val > 50 ? Color.orange : Color.cyan))
                                .frame(width: max(2, geo.size.width * CGFloat(val / 100.0)))
                        }
                    }
                    .frame(height: 4)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
            }
        }
    }
    
    // MARK: - GPU Section
    
    private var gpuCard: some View {
        let snap = engine.snapshot
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "38BDF8"))
                    Text("ĐỒ HOẠ (GPU)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Text(snap.gpu.modelName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                    
                    Text("\(String(format: "%.1f", snap.gpu.temperature))°C")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(tempColor(snap.gpu.temperature))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(tempColor(snap.gpu.temperature).opacity(0.12)))
                }
            }
            
            HStack(spacing: 20) {
                // Ring Gauge
                circularGauge(
                    percentage: snap.gpu.utilization,
                    color: Color(hex: "38BDF8"),
                    label: "\(Int(snap.gpu.utilization))%",
                    caption: "Công suất"
                )
                .frame(width: 90, height: 90)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        statRow(label: "Renderer:", value: "\(Int(snap.gpu.rendererUtilization))%", color: .white)
                        statRow(label: "Tiler:", value: "\(Int(snap.gpu.tilerUtilization))%", color: Color(hex: "38BDF8"))
                        if snap.gpu.inUseMemory > 0 {
                            let inUseStr = ByteCountFormatter.string(fromByteCount: Int64(snap.gpu.inUseMemory), countStyle: .memory)
                            statRow(label: "VRAM:", value: inUseStr, color: .white.opacity(0.7))
                        }
                    }
                    
                    // Sparkline
                    sparklineView(data: engine.gpuHistory, color: Color(hex: "38BDF8"))
                        .frame(height: 38)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
    
    // MARK: - RAM & Memory Pressure Section
    
    private var ramAndPressureCard: some View {
        let snap = engine.snapshot
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "memorychip.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "A855F7"))
                    Text("BỘ NHỚ RAM & ÁP LỰC HỆ THỐNG")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                Text("\(snap.ram.formattedUsed) / \(snap.ram.formattedTotal) (\(Int(snap.ram.usagePercentage))%)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Stacked RAM Bar
            ramBreakdownBar(ram: snap.ram)
            
            // Pressure Banner & Breakdown
            HStack(spacing: 16) {
                // Pressure status box
                HStack(spacing: 10) {
                    Circle()
                        .fill(pressureColor(snap.ram.pressureLevel))
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Áp lực bộ nhớ: \(snap.ram.pressureLevel.title)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(pressureColor(snap.ram.pressureLevel))
                        Text(snap.ram.pressureLevel.statusDescription)
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(pressureColor(snap.ram.pressureLevel).opacity(0.08))
                )
                
                if snap.ram.swapTotalBytes > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("SWAP ĐÃ DÙNG")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                        Text("\(snap.ram.formattedSwapUsed) / \(snap.ram.formattedSwapTotal)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
    
    private func ramBreakdownBar(ram: SystemRAMStats) -> some View {
        let total = Double(ram.totalBytes)
        let wiredW = total > 0 ? CGFloat(Double(ram.wiredBytes) / total) : 0
        let activeW = total > 0 ? CGFloat(Double(ram.activeBytes) / total) : 0
        let compW = total > 0 ? CGFloat(Double(ram.compressedBytes) / total) : 0
        
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Color(hex: "38BDF8")).frame(width: max(0, geo.size.width * wiredW))
                    Rectangle().fill(Color.orange).frame(width: max(0, geo.size.width * activeW))
                    Rectangle().fill(Color(hex: "A855F7")).frame(width: max(0, geo.size.width * compW))
                    Rectangle().fill(Color.white.opacity(0.12))
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            
            HStack(spacing: 12) {
                legendItem(label: "Wired: \(ByteCountFormatter.string(fromByteCount: Int64(ram.wiredBytes), countStyle: .memory))", color: Color(hex: "38BDF8"))
                legendItem(label: "Active: \(ByteCountFormatter.string(fromByteCount: Int64(ram.activeBytes), countStyle: .memory))", color: Color.orange)
                legendItem(label: "Compressed: \(ByteCountFormatter.string(fromByteCount: Int64(ram.compressedBytes), countStyle: .memory))", color: Color(hex: "A855F7"))
                legendItem(label: "Free: \(ByteCountFormatter.string(fromByteCount: Int64(ram.freeBytes), countStyle: .memory))", color: Color.white.opacity(0.4))
            }
        }
    }
    
    private func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    // MARK: - Controls Bar
    
    private var controlsBar: some View {
        HStack {
            Text("Tần suất cập nhật:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
            
            HStack(spacing: 6) {
                ForEach([1.0, 1.5, 3.0, 5.0], id: \.self) { interval in
                    let isSel = engine.updateInterval == interval
                    Button(action: {
                        engine.updateInterval = interval
                    }) {
                        Text("\(String(format: "%.1f", interval))s")
                            .font(.system(size: 10, weight: isSel ? .bold : .medium))
                            .foregroundColor(isSel ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(isSel ? Color.white.opacity(0.14) : Color.white.opacity(0.03))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            Button(action: {
                engine.refreshNow()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text("Cập nhật ngay")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
    }
    
    // MARK: - Subcomponents
    
    private func circularGauge(percentage: Double, color: Color, label: String, caption: String) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 7)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(min(1.0, max(0.0, percentage / 100.0))))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.6), color]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percentage)
            
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(caption)
                    .font(.system(size: 8.5))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
    
    private func sparklineView(data: [Double], color: Color) -> some View {
        GeometryReader { geo in
            let points = data.enumerated().map { (idx, val) -> CGPoint in
                let x = geo.size.width * CGFloat(idx) / CGFloat(max(1, engine.maxHistoryCount - 1))
                let clamped = min(100.0, max(0.0, val))
                let y = geo.size.height * (1.0 - CGFloat(clamped / 100.0))
                return CGPoint(x: x, y: y)
            }
            
            ZStack {
                // Background subtle grid
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Color.white.opacity(0.04), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                if points.count > 1 {
                    // Line
                    Path { p in
                        p.move(to: points[0])
                        for pt in points.dropFirst() {
                            p.addLine(to: pt)
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    
                    // Fill area underneath
                    Path { p in
                        p.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        p.addLine(to: points[0])
                        for pt in points.dropFirst() {
                            p.addLine(to: pt)
                        }
                        p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.18), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.2))
        )
    }
    
    private func statRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
    
    private func tempColor(_ temp: Double) -> Color {
        if temp >= 85 { return Color.red }
        if temp >= 70 { return Color.orange }
        if temp >= 55 { return Color.yellow }
        return Color(hex: "10B981")
    }
    
    private func pressureColor(_ level: MemoryPressureLevel) -> Color {
        switch level {
        case .normal: return Color(hex: "10B981")
        case .warning: return Color.orange
        case .critical: return Color.red
        }
    }
}
