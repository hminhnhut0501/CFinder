import SwiftUI
import AppKit

public struct FloatingOCRHUDView: View {
    let isSuccess: Bool
    let title: String
    let message: String
    let preview: String?
    let count: Int?
    let isURL: Bool
    let isTable: Bool
    let multiRegionCount: Int
    let onOpenURL: (() -> Void)?
    let onDismiss: () -> Void
    
    @State private var isHovered: Bool = false
    
    public init(
        isSuccess: Bool,
        title: String,
        message: String,
        preview: String? = nil,
        count: Int? = nil,
        isURL: Bool = false,
        isTable: Bool = false,
        multiRegionCount: Int = 1,
        onOpenURL: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.isSuccess = isSuccess
        self.title = title
        self.message = message
        self.preview = preview
        self.count = count
        self.isURL = isURL
        self.isTable = isTable
        self.multiRegionCount = multiRegionCount
        self.onOpenURL = onOpenURL
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Left Status Icon Badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isSuccess
                                ? [Color(red: 0.15, green: 0.85, blue: 0.55), Color(red: 0.05, green: 0.65, blue: 0.45)]
                                : [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 0.9, green: 0.4, blue: 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .shadow(
                        color: isSuccess
                            ? Color.green.opacity(0.4)
                            : Color.orange.opacity(0.4),
                        radius: 8,
                        y: 3
                    )
                
                Image(systemName: isSuccess ? (isURL ? "link" : (isTable ? "tablecells" : "checkmark")) : "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Middle Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if isTable {
                        Text("BẢNG TSV")
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.cyan.opacity(0.18)))
                    }
                    
                    if multiRegionCount > 1 {
                        Text("\(multiRegionCount) VÙNG")
                            .font(.system(size: 9.5, weight: .heavy))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                    }
                    
                    if let count = count, count > 0 {
                        Text("\(count) ký tự")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                            )
                    }
                }
                
                if let preview = preview, !preview.isEmpty {
                    Text("\"\(preview)\"")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                } else {
                    Text(message)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(2)
                }
            }
            
            Spacer(minLength: 8)
            
            // Smart Action: Open URL Button if link detected
            if isURL, let onOpenURL = onOpenURL {
                Button(action: onOpenURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.system(size: 11, weight: .medium))
                        Text("Mở liên kết")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.7))
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Right Dismiss Button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 320, maxWidth: 480)
        .background(
            ZStack {
                // Frosted Liquid Glass Background
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.17).opacity(0.88))
                
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
