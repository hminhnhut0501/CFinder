import SwiftUI
import AppKit
import SFinderCore

public struct RecordingIndicatorHUDView: View {
    @ObservedObject private var engine = ScreenRecorderEngine.shared
    @State private var isPulsing = false
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 10) {
            // Pulsing Red Dot
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "EF4444"))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 1.25 : 0.85)
                    .opacity(isPulsing ? 1.0 : 0.45)
                    .animation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                
                Text("REC")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "EF4444"))
            }
            
            // Timer Display
            Text(engine.formattedDuration)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer(minLength: 4)
            
            // Stop Recording Button
            Button(action: {
                engine.stopRecording()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .black))
                    Text("Dừng")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(hex: "EF4444").opacity(0.85))
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 195, height: 38)
        .background(
            Capsule()
                .fill(Color(hex: "111215").opacity(0.90))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 12, y: 4)
        )
        .onAppear {
            isPulsing = true
        }
    }
}
