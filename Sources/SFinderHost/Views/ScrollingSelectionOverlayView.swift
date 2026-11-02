import SwiftUI
import AppKit

public struct ScrollingSelectionOverlayView: View {
    let screenOrigin: CGPoint
    let onConfirm: (CGRect) -> Void
    let onCancel: () -> Void
    
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    
    public init(screenOrigin: CGPoint, onConfirm: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.screenOrigin = screenOrigin
        self.onConfirm = onConfirm
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
                // Dimming backdrop
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
                            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                        
                        VStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.and.down.and.sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(Int(rect.width)) × \(Int(rect.height)) px")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "111113").opacity(0.88))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                            )
                            .padding(.bottom, -30)
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                }
                
                // Hint tooltip
                if selectionRect == nil {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Chụp ảnh cuộn (Scrolling Capture)")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundColor(.white)
                        
                        Text("Kéo chuột để chọn vùng muốn chụp cuộn • Bấm Esc để thoát")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "18181B").opacity(0.90))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
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
                        guard let rect = selectionRect, rect.width >= 50 && rect.height >= 50 else {
                            startPoint = nil
                            currentPoint = nil
                            return
                        }
                        let screenX = screenOrigin.x + rect.minX
                        let screenY = screenOrigin.y + (geo.size.height - rect.maxY)
                        let screenRect = CGRect(x: screenX, y: screenY, width: rect.width, height: rect.height)
                        onConfirm(screenRect)
                    }
            )
        }
    }
}
