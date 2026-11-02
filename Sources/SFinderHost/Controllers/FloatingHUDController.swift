import Cocoa
import SwiftUI
import SFinderCore

@MainActor
public final class FloatingHUDController: NSObject {
    public static let shared = FloatingHUDController()
    
    private var window: NSPanel?
    private var dismissTimer: Timer?
    
    override private init() {
        super.init()
        setupListeners()
    }
    
    private func setupListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOCRCompleted(_:)),
            name: ScreenOCREngine.ocrCompletedNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOCRFailed(_:)),
            name: ScreenOCREngine.ocrFailedNotification,
            object: nil
        )
    }
    
    @objc private func handleOCRCompleted(_ notif: Notification) {
        guard let info = notif.userInfo,
              let count = info["count"] as? Int,
              let preview = info["preview"] as? String else {
            return
        }
        
        let isURL = (info["isURL"] as? Bool) ?? false
        let isTable = (info["isTable"] as? Bool) ?? false
        let multiRegionCount = (info["multiRegionCount"] as? Int) ?? 1
        let fullText = (info["text"] as? String) ?? preview
        
        let titleSuffix = multiRegionCount > 1 ? " (Gộp \(multiRegionCount) vùng)" : ""
        let title = "Đã sao chép vào Clipboard\(titleSuffix)"
        
        showHUD(
            isSuccess: true,
            title: title,
            message: "✓ Đã nhận diện \(count) ký tự",
            preview: preview,
            count: count,
            isURL: isURL,
            isTable: isTable,
            multiRegionCount: multiRegionCount,
            onOpenURL: isURL ? {
                if let url = URL(string: fullText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    NSWorkspace.shared.open(url)
                }
            } : nil
        )
    }
    
    @objc private func handleOCRFailed(_ notif: Notification) {
        let msg = (notif.userInfo?["message"] as? String) ?? "Không phát hiện văn bản."
        showHUD(
            isSuccess: false,
            title: "CFinder OCR",
            message: msg,
            preview: nil,
            count: nil,
            isURL: false,
            isTable: false,
            multiRegionCount: 1,
            onOpenURL: nil
        )
    }
    
    public func showHUD(
        isSuccess: Bool,
        title: String,
        message: String,
        preview: String?,
        count: Int?,
        isURL: Bool = false,
        isTable: Bool = false,
        multiRegionCount: Int = 1,
        onOpenURL: (() -> Void)? = nil
    ) {
        dismissTimer?.invalidate()
        
        let hudView = FloatingOCRHUDView(
            isSuccess: isSuccess,
            title: title,
            message: message,
            preview: preview,
            count: count,
            isURL: isURL,
            isTable: isTable,
            multiRegionCount: multiRegionCount,
            onOpenURL: onOpenURL,
            onDismiss: { [weak self] in
                self?.hideHUD()
            }
        )
        
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.wantsLayer = true
        
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 72),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = false
            self.window = panel
        }
        
        guard let panel = window else { return }
        panel.contentView = hostingView
        panel.layoutIfNeeded()
        
        // Position at top center of active screen, 48px below menu bar
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let hudWidth: CGFloat = 380
        let hudHeight: CGFloat = 72
        
        let x = screenFrame.midX - (hudWidth / 2)
        let targetY = screenFrame.maxY - hudHeight - 16
        let startY = screenFrame.maxY + 20
        
        panel.setFrame(NSRect(x: x, y: startY, width: hudWidth, height: hudHeight), display: true)
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        
        // Smooth slide & fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrame(NSRect(x: x, y: targetY, width: hudWidth, height: hudHeight), display: true)
        }
        
        // Auto-dismiss after 2.8 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideHUD()
            }
        }
    }
    
    public func showToast(
        icon: String,
        iconColor: Color = .white,
        title: String,
        subtitle: String,
        duration: TimeInterval = 2.4
    ) {
        dismissTimer?.invalidate()
        
        let toastView = FloatingToastHUDView(
            icon: icon,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            onDismiss: { [weak self] in
                self?.hideHUD()
            }
        )
        
        let hostingView = NSHostingView(rootView: toastView)
        hostingView.wantsLayer = true
        
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 58),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = false
            self.window = panel
        }
        
        guard let panel = window else { return }
        panel.contentView = hostingView
        panel.layoutIfNeeded()
        
        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let hudWidth: CGFloat = 360
        let hudHeight: CGFloat = 58
        
        let x = screenFrame.midX - (hudWidth / 2)
        let targetY = screenFrame.maxY - hudHeight - 16
        let startY = screenFrame.maxY + 20
        
        panel.setFrame(NSRect(x: x, y: startY, width: hudWidth, height: hudHeight), display: true)
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrame(NSRect(x: x, y: targetY, width: hudWidth, height: hudHeight), display: true)
        }
        
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideHUD()
            }
        }
    }
    
    public func hideHUD() {
        guard let panel = window, panel.isVisible else { return }
        dismissTimer?.invalidate()
        dismissTimer = nil
        
        let currentFrame = panel.frame
        let targetY = currentFrame.origin.y + 24
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
            panel.animator().setFrame(NSRect(x: currentFrame.origin.x, y: targetY, width: currentFrame.width, height: currentFrame.height), display: true)
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
