import SwiftUI
import AppKit
import SFinderCore

public struct SnapPreviewOverlayView: View {
    let position: SnapPosition
    
    public init(position: SnapPosition) {
        self.position = position
    }
    
    public var body: some View {
        ZStack {
            // Liquid Frosted Glass Area
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .background(
                    VisualEffectView(material: .popover, blendingMode: .withinWindow, state: .active)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.white.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.black.opacity(0.25), radius: 16, y: 4)
            
            // Central Position Indicator Pill
            HStack(spacing: 8) {
                Image(systemName: position.icon)
                    .font(.system(size: 14, weight: .bold))
                
                Text(position.title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
            )
        }
        .padding(4)
        .ignoresSafeArea()
    }
}
