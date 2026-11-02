import Foundation
import AppKit

public enum SystemPowerAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case allowIdleSleep = "allow_idle"
    case sleepNow = "sleep_now"
    case shutDown = "shutdown"
    case displaySleep = "display_sleep"
    case lockScreen = "lock_screen"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .allowIdleSleep: return "Ngủ tự nhiên"
        case .sleepNow: return "Ngủ máy"
        case .shutDown: return "Tắt máy"
        case .displaySleep: return "Tắt màn hình"
        case .lockScreen: return "Khoá máy"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .allowIdleSleep: return "Giải phóng chống ngủ, Mac sẽ ngủ theo thời gian nghỉ tiết kiệm pin"
        case .sleepNow: return "Lập tức đưa hệ thống Mac vào trạng thái ngủ sâu ngay khi hoàn tất"
        case .shutDown: return "Tắt nguồn an toàn toàn bộ máy Mac sau khi hoàn thành phiên làm việc"
        case .displaySleep: return "Tắt màn hình ngay nhưng vẫn giữ CPU chạy tác vụ nền nếu cần"
        case .lockScreen: return "Khoá màn hình bảo vệ quyền riêng tư ngay lập tức"
        }
    }
    
    public var icon: String {
        switch self {
        case .allowIdleSleep: return "powersleep"
        case .sleepNow: return "moon.zzz.fill"
        case .shutDown: return "power"
        case .displaySleep: return "display"
        case .lockScreen: return "lock.fill"
        }
    }
    
    // MARK: - Safe System Execution Handlers
    
    @discardableResult
    public static func executeSleep() -> Bool {
        NSLog("[SystemPowerAction] Executing System Sleep...")
        let script = "tell application \"System Events\" to sleep"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let err = error {
                NSLog("[SystemPowerAction] Sleep AppleScript error: %@", err)
                return false
            }
            return true
        }
        return false
    }
    
    @discardableResult
    public static func executeShutDown() -> Bool {
        NSLog("[SystemPowerAction] Executing System Shut Down...")
        let script = "tell application \"System Events\" to shut down"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let err = error {
                NSLog("[SystemPowerAction] Shut Down AppleScript error: %@", err)
                return false
            }
            return true
        }
        return false
    }
    
    @discardableResult
    public static func executeDisplaySleep() -> Bool {
        NSLog("[SystemPowerAction] Executing Display Sleep...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
            return true
        } catch {
            NSLog("[SystemPowerAction] Display sleep pmset failed: %@", error.localizedDescription)
            return false
        }
    }
    
    @discardableResult
    public static func executeLock() -> Bool {
        NSLog("[SystemPowerAction] Executing Screen Lock...")
        let script = "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }
    
    public func execute() {
        switch self {
        case .allowIdleSleep:
            break
        case .sleepNow:
            Self.executeSleep()
        case .shutDown:
            Self.executeShutDown()
        case .displaySleep:
            Self.executeDisplaySleep()
        case .lockScreen:
            Self.executeLock()
        }
    }
}
