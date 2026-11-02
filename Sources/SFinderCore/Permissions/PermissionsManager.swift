import Foundation
import AppKit
import ServiceManagement
import ApplicationServices
import CoreGraphics

public enum PermissionType: String, CaseIterable, Identifiable, Sendable {
    case screenCapture = "screen_capture"
    case accessibility = "accessibility"
    case finderSync = "finder_sync"
    case launchAtLogin = "launch_at_login"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .screenCapture: return "Ghi màn hình (Screen Recording)"
        case .accessibility: return "Trợ năng & Phím tắt (Accessibility)"
        case .finderSync: return "Tiện ích mở rộng Finder (Finder Sync)"
        case .launchAtLogin: return "Khởi động cùng máy (Launch at Login)"
        }
    }
    
    public var purpose: String {
        switch self {
        case .screenCapture: return "Cần thiết để quét chụp và nhận diện văn bản OCR tiếng Việt trên màn hình."
        case .accessibility: return "Cho phép bắt phím tắt toàn cục và tương tác với Finder nhanh chóng."
        case .finderSync: return "Tích hợp menu chuột phải và thanh công cụ trực tiếp trong macOS Finder."
        case .launchAtLogin: return "Tự động chạy SFinder ở thanh Menu Bar khi đăng nhập máy Mac."
        }
    }
    
    public var iconName: String {
        switch self {
        case .screenCapture: return "display.trianglebadge.exclamationmark"
        case .accessibility: return "figure.roll"
        case .finderSync: return "folder.badge.gearshape"
        case .launchAtLogin: return "power"
        }
    }
}

public struct PermissionStatus: Identifiable, Sendable {
    public let type: PermissionType
    public let isGranted: Bool
    public var id: String { type.id }
}

public final class PermissionsManager: @unchecked Sendable {
    public static let shared = PermissionsManager()
    
    public static let permissionsDidChangeNotification = Notification.Name("com.sfinder.permissions.didChange")
    
    private init() {}
    
    // MARK: - Query Permissions
    
    public var isScreenCaptureGranted: Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    public var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }
    
    public var isFinderExtensionEnabled: Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-m", "-i", "com.sfinder.app.sync"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            return output.contains("+") && output.contains("com.sfinder.app.sync")
        }
        return false
    }
    
    public var isLaunchAtLoginEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    public var allStatus: [PermissionStatus] {
        return [
            PermissionStatus(type: .screenCapture, isGranted: isScreenCaptureGranted),
            PermissionStatus(type: .accessibility, isGranted: isAccessibilityGranted),
            PermissionStatus(type: .finderSync, isGranted: isFinderExtensionEnabled),
            PermissionStatus(type: .launchAtLogin, isGranted: isLaunchAtLoginEnabled)
        ]
    }
    
    public var requiredCount: Int {
        return 3 // ScreenCapture, Accessibility, FinderSync
    }
    
    public var grantedRequiredCount: Int {
        var count = 0
        if isScreenCaptureGranted { count += 1 }
        if isAccessibilityGranted { count += 1 }
        if isFinderExtensionEnabled { count += 1 }
        return count
    }
    
    public var isHealthOptimal: Bool {
        return isScreenCaptureGranted && isAccessibilityGranted && isFinderExtensionEnabled
    }
    
    // MARK: - Request Permissions & Actions
    
    public func requestScreenCapture() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        openSystemSettings(for: .screenCapture)
        notifyChange()
    }
    
    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings(for: .accessibility)
        notifyChange()
    }
    
    public func enableFinderExtension() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-e", "use", "-i", "com.sfinder.app.sync"]
        try? task.run()
        task.waitUntilExit()
        
        // Open Extensions preferences
        openSystemSettings(for: .finderSync)
        notifyChange()
    }
    
    public func toggleLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[PermissionsManager] Error setting launch at login: %@", error.localizedDescription)
        }
        notifyChange()
    }
    
    public func openSystemSettings(for type: PermissionType) {
        let urlString: String
        switch type {
        case .screenCapture:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .finderSync:
            urlString = "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        case .launchAtLogin:
            urlString = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.permissionsDidChangeNotification, object: self)
        }
    }
}
