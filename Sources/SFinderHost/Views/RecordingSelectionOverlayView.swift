import SwiftUI
import AppKit

public struct RecordingSelectionOverlayView: View {
    let screenOrigin: CGPoint
    let onConfirmRegion: (CGRect) -> Void
    let onConfirmFullScreen: () -> Void
    let onCancel: () -> Void
    
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    
    public init(
        screenOrigin: CGPoint,
        onConfirmRegion: @escaping (CGRect) -> Void,
        onConfirmFullScreen: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screenOrigin = screenOrigin
        self.onConfirmRegion = onConfirmRegion
        self.onConfirmFullScreen = onConfirmFullScreen
        self.onCancel = onCancel
    }
    
    private var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(start.x - current.x)
        let h = abs(start.y - current.y)
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimming backdrop with cutout
                Color.black.opacity(0.35)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        Group {
                            if let rect = selectionRect {
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .blendMode(.destinationOut)
                            }
                        }
                    )
                    .compositingGroup()
                
                // Active Selection Box
                if let rect = selectionRect, rect.width > 5 && rect.height > 5 {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color(hex: "EF4444"), lineWidth: 2)
                        
                        VStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: "EF4444"))
                                    .frame(width: 7, height: 7)
                                Text("REC  \(Int(rect.width)) × \(Int(rect.height)) px")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "111113").opacity(0.92))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                            )
                            .padding(.bottom, -30)
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                }
                
                // Helper Card
                if selectionRect == nil {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(hex: "EF4444"))
                            Text("Quay màn hình (Screen Recording)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Kéo chuột để quét vùng chọn cần quay video\nBấm Phím cách (Space) để quay toàn màn hình • Bấm Esc để huỷ")
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.75))
                            .lineSpacing(3)
                        
                        HStack(spacing: 10) {
                            Button(action: onConfirmFullScreen) {
                                HStack(spacing: 5) {
                                    Image(systemName: "macwindow")
                                    Text("Quay toàn màn hình (Space)")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: onCancel) {
                                Text("Huỷ (Esc)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "18181B").opacity(0.92))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                    )
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startPoint == nil {
                            startPoint = value.startLocation
                        }
                        currentPoint = value.location
                    }
                    .onEnded { value in
                        guard let rect = selectionRect, rect.width >= 40 && rect.height >= 40 else {
                            startPoint = nil
                            currentPoint = nil
                            return
                        }
                        let screenX = screenOrigin.x + rect.minX
                        let screenY = screenOrigin.y + (geo.size.height - rect.maxY)
                        let screenRect = CGRect(x: screenX, y: screenY, width: rect.width, height: rect.height)
                        onConfirmRegion(screenRect)
                    }
            )
        }
    }
}
