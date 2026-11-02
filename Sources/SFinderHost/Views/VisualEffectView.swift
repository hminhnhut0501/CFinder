import SwiftUI
import AppKit

public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    
    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.autoresizingMask = [.width, .height]
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var strokeOpacity: Double
    public var fillOpacity: Double
    
    public init(cornerRadius: CGFloat = 16, strokeOpacity: Double = 0.25, fillOpacity: Double = 0.08) {
        self.cornerRadius = cornerRadius
        self.strokeOpacity = strokeOpacity
        self.fillOpacity = fillOpacity
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strokeOpacity),
                                Color.white.opacity(strokeOpacity * 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}



extension View {
    public func glassCard(
        cornerRadius: CGFloat = 16,
        strokeOpacity: Double = 0.25,
        fillOpacity: Double = 0.08
    ) -> some View {
        self.modifier(GlassCardModifier(
            cornerRadius: cornerRadius,
            strokeOpacity: strokeOpacity,
            fillOpacity: fillOpacity
        ))
    }
}
