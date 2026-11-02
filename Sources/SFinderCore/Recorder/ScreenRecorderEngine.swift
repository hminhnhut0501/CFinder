import Foundation
import CoreGraphics
import AppKit
import AudioToolbox

/// Trình quản lý Ghi Màn Hình tốc độ cao chuẩn Apple Silicon VideoToolbox của CFinder
@MainActor
public final class ScreenRecorderEngine: ObservableObject {
    public static let shared = ScreenRecorderEngine()
    
    // MARK: - Published State
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var currentOutputFileURL: URL?
    @Published public private(set) var currentTargetRect: CGRect?
    
    // Callbacks
    public var onStateChanged: ((Bool) -> Void)?
    public var onShowToast: ((String, String, String) -> Void)?
    
    // Internal Process Management
    private var process: Process?
    private var inputPipe: Pipe?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    
    private init() {}
    
    // MARK: - Formatted Duration
    public var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - Actions
    
    /// Bắt đầu hoặc dừng ghi màn hình (Toggle)
    public func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            // Hiển thị lớp phủ quét vùng chọn để ghi
            NotificationCenter.default.post(name: NSNotification.Name("CFinderPresentRecordingOverlay"), object: nil)
        }
    }
    
    /// Khởi động phiên ghi màn hình (Toàn màn hình hoặc Vùng chọn cụ thể)
    /// - Parameter targetRect: Vùng màn hình toạ độ Cocoa (nil = Toàn màn hình)
    public func startRecording(targetRect: CGRect? = nil) {
        guard !isRecording else { return }
        
        // 1. Gửi thông báo ẩn tất cả cửa sổ của CFinder để không lọt vào video
        NotificationCenter.default.post(name: NSNotification.Name("CFinderHideAllWindowsForCapture"), object: nil)
        
        self.currentTargetRect = targetRect
        
        // 2. Tạo đường dẫn tệp trên Desktop
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let fileURL = desktopURL.appendingPathComponent("CFinder_Record_\(timestamp).mov")
        self.currentOutputFileURL = fileURL
        
        // 3. Chuẩn bị đối số cho screencapture CLI
        // -v: Chế độ quay video phần cứng native của macOS
        // -k: Hiệu ứng vòng tròn lan toả khi nhấp chuột (Click ripples)
        var args = ["-v"]
        
        let showClicks = UserDefaults.standard.object(forKey: "CFinder_Record_ShowClicks") as? Bool ?? true
        if showClicks {
            args.append("-k")
        }
        
        let recordMic = UserDefaults.standard.bool(forKey: "CFinder_Record_Microphone")
        if recordMic {
            args.append("-g")
        }
        
        let recordSysAudio = UserDefaults.standard.bool(forKey: "CFinder_Record_SystemAudio")
        if recordSysAudio {
            args.append("-A")
        }
        
        // Cấu hình vùng chọn cụ thể nếu có
        if let rect = targetRect, rect.width >= 30 && rect.height >= 30 {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
            let cliY = Int(primaryHeight - rect.maxY)
            let cliX = Int(rect.minX)
            let cliW = Int(rect.width)
            let cliH = Int(rect.height)
            args.append("-R\(cliX),\(cliY),\(cliW),\(cliH)")
        }
        
        args.append(fileURL.path)
        
        // 4. Khởi chạy tiến trình
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = args
        
        let inPipe = Pipe()
        p.standardInput = inPipe
        
        // 4. Đợi 120ms để WindowServer macOS dọn sạch hoàn toàn lớp phủ chọn vùng khỏi bộ đệm màn hình
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self = self else { return }
            do {
                try p.run()
                self.process = p
                self.inputPipe = inPipe
                self.isRecording = true
                self.recordingStartTime = Date()
                self.recordingDuration = 0
                
                // Phát âm thanh bắt đầu ghi
                AudioServicesPlaySystemSound(1113)
                
                // Chạy timer cập nhật thời lượng ghi
                self.durationTimer?.invalidate()
                self.durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self, let start = self.recordingStartTime else { return }
                        self.recordingDuration = Date().timeIntervalSince(start)
                    }
                }
                
                // Gửi thông báo mở thanh chỉ báo nổi (Floating Recording HUD) kèm vùng chọn
                var userInfo: [String: Any] = ["url": fileURL]
                if let rect = targetRect {
                    userInfo["region"] = NSValue(rect: rect)
                }
                NotificationCenter.default.post(
                    name: NSNotification.Name("CFinderShowRecordingHUD"),
                    object: nil,
                    userInfo: userInfo
                )
                
                self.onStateChanged?(true)
            } catch {
                NSLog("[ScreenRecorderEngine] Failed to run screencapture: %@", error.localizedDescription)
                self.isRecording = false
                self.currentTargetRect = nil
                NotificationCenter.default.post(name: NSNotification.Name("CFinderRestoreWindowsAfterCapture"), object: nil)
            }
        }
    }
    
    /// Dừng và hoàn tất tệp video
    public func stopRecording() {
        guard isRecording, let p = process else { return }
        
        durationTimer?.invalidate()
        durationTimer = nil
        
        // Gửi Ctrl-C (0x03) vào stdin và ngắt tiến trình để screencapture hoàn thiện cấu trúc tệp MOV
        if let pipe = inputPipe {
            pipe.fileHandleForWriting.write(Data([0x03]))
            try? pipe.fileHandleForWriting.close()
        }
        p.interrupt()
        
        self.process = nil
        self.inputPipe = nil
        self.isRecording = false
        self.currentTargetRect = nil
        
        // Đóng thanh chỉ báo nổi
        NotificationCenter.default.post(name: NSNotification.Name("CFinderHideRecordingHUD"), object: nil)
        
        // Phát âm thanh hoàn thành ghi
        AudioServicesPlaySystemSound(1114)
        
        let outputURL = currentOutputFileURL
        
        // Đợi tiến trình ghi đĩa hoàn tất trên nền phụ để không khoá giao diện
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            p.waitUntilExit()
            
            Task { @MainActor [weak self] in
                guard let outputURL = outputURL, FileManager.default.fileExists(atPath: outputURL.path) else {
                    NotificationCenter.default.post(name: NSNotification.Name("CFinderRestoreWindowsAfterCapture"), object: nil)
                    return
                }
                
                // 1. Sao chép tệp video vào Clipboard hệ thống
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([outputURL as NSURL])
                
                // 2. Mở Finder và trỏ vào video vừa lưu
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                
                // 3. Hiển thị thông báo Toast
                let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
                let sizeMB = String(format: "%.1f MB", Double(size) / (1024 * 1024))
                self?.onShowToast?("record.circle.fill", "Đã lưu video quay màn hình!", "\(outputURL.lastPathComponent) (\(sizeMB)) đã lưu tại Desktop")
                
                self?.onStateChanged?(false)
            }
        }
    }
}
