import SwiftUI
import AppKit
import SFinderCore

@MainActor
public struct VideoNormalizerHUDView: View {
    @ObservedObject var coordinator: VideoNormalizerBatchCoordinator
    let onCancel: () -> Void
    let onDismiss: () -> Void
    let onRevealInFinder: () -> Void
    
    @State private var isHovered: Bool = false
    
    public init(
        coordinator: VideoNormalizerBatchCoordinator = .shared,
        onCancel: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onRevealInFinder: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.onCancel = onCancel
        self.onDismiss = onDismiss
        self.onRevealInFinder = onRevealInFinder
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            // Header Row: Icon + Title/Status + Action/Close Button
            HStack(spacing: 12) {
                // Left Icon Badge
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: coordinator.isCompleted
                                    ? [Color(red: 0.15, green: 0.85, blue: 0.55), Color(red: 0.05, green: 0.65, blue: 0.45)]
                                    : [Color(red: 0.1, green: 0.7, blue: 1.0), Color(red: 0.35, green: 0.3, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                        .shadow(
                            color: coordinator.isCompleted ? Color.green.opacity(0.35) : Color.cyan.opacity(0.35),
                            radius: 8,
                            y: 2
                        )
                    
                    Image(systemName: coordinator.isCompleted ? "checkmark" : "film.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Titles & Subtitles
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(coordinator.isCompleted ? "Chuẩn hoá hoàn tất!" : "Chuẩn hoá Video")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        
                        if !coordinator.isCompleted && coordinator.totalFilesCount > 0 {
                            Text("[\(coordinator.currentFileIndex)/\(coordinator.totalFilesCount)]")
                                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.cyan.opacity(0.18)))
                        }
                        
                        if !coordinator.currentStrategyDesc.isEmpty && !coordinator.isCompleted {
                            Text(coordinator.currentStrategyDesc)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                    }
                    
                    if coordinator.isCompleted {
                        Text(coordinator.completionSummary)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text(coordinator.currentFileName.isEmpty ? "Đang khởi tạo..." : coordinator.currentFileName)
                            .font(.system(size: 11.5))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                Spacer(minLength: 8)
                
                // Actions: Open in Finder (if complete) or Cancel/Dismiss
                if coordinator.isCompleted {
                    Button(action: onRevealInFinder) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10.5))
                            Text("Mở Finder")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue.opacity(0.8)))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onCancel) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                            Text("Hủy")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Progress Bar & Real-time Metrics (while processing)
            if !coordinator.isCompleted {
                VStack(spacing: 6) {
                    // Glowing Gradient Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 7)
                            
                            // Fill
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan, Color(red: 0.4, green: 0.5, blue: 1.0)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(coordinator.currentProgress))), height: 7)
                                .animation(.easeOut(duration: 0.15), value: coordinator.currentProgress)
                        }
                    }
                    .frame(height: 7)
                    
                    // Metrics Row
                    HStack {
                        // Percent
                        Text("\(Int(coordinator.currentProgress * 100))%")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                        
                        if coordinator.currentSpeed > 0.05 {
                            Text("•  \(String(format: "%.1f", coordinator.currentSpeed))x")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        
                        if coordinator.currentFPS > 1 {
                            Text("•  \(Int(coordinator.currentFPS)) fps")
                                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        
                        Spacer()
                        
                        if let eta = coordinator.currentETA, eta > 0.5 {
                            Text("còn ~\(Int(ceil(eta)))s")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        
                        if coordinator.totalSavedBytes > 0 {
                            let mb = Double(coordinator.totalSavedBytes) / (1024.0 * 1024.0)
                            Text("• Tiết kiệm \(String(format: "%.1f", mb)) MB")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(Color(red: 0.3, green: 0.9, blue: 0.6))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 380, maxWidth: 460)
        .background(
            ZStack {
                // Frosted Liquid Glass Background
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.92))
                
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
        .onHover { h in
            isHovered = h
        }
    }
}
