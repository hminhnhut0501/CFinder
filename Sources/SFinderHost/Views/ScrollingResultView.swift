import SwiftUI
import AppKit
import SFinderCore

public struct ScrollingResultView: View {
    let image: NSImage
    let onDismiss: () -> Void
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var copiedNotice: Bool = true
    
    public init(image: NSImage, onDismiss: @escaping () -> Void) {
        self.image = image
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 30, height: 30)
                    
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ảnh chụp cuộn hoàn tất")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(Int(image.size.width)) × \(Int(image.size.height)) px • Đã tự động chép vào Clipboard")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // OCR Button
                Button(action: {
                    Task {
                        _ = try? await ScreenOCREngine.shared.recognizeFromClipboard()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "text.viewfinder")
                        Text("Quét chữ OCR")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Trích xuất chữ / bảng từ ảnh dài này")
                
                // Close button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(6)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.02))
            
            Divider().background(Color.white.opacity(0.08))
            
            // Middle: Scrollable Image Viewer
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoomScale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            }
            .background(Color.black.opacity(0.45))
            
            Divider().background(Color.white.opacity(0.08))
            
            // Bottom Action Bar
            HStack(spacing: 12) {
                // Zoom Controls
                HStack(spacing: 6) {
                    Button(action: { zoomScale = max(0.4, zoomScale - 0.2) }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(Int(zoomScale * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44)
                    
                    Button(action: { zoomScale = min(3.0, zoomScale + 0.2) }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                
                Spacer()
                
                // Copy Button
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects([image])
                    copiedNotice = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                        Text(copiedNotice ? "Đã chép" : "Chép vào Clipboard")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                // Open in Apple Preview
                Button(action: openInApplePreview) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Mở Xem trước")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                // Save to File
                Button(action: saveToFile) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Lưu ảnh (⌘S)")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.02))
        }
        .frame(width: 760, height: 640)
        .background(
            Color(hex: "131315")
        )
    }
    
    private func saveToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        savePanel.nameFieldStringValue = "SFinder_ChupCuon_\(formatter.string(from: Date())).png"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: url)
                }
            }
        }
    }
    
    private func openInApplePreview() {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SFinder_ChupCuon_\(UUID().uuidString).png")
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)
        }
    }
}
