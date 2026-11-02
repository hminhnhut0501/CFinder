import Foundation
import AppKit

public enum IPCActionType: String, Codable, Sendable {
    case showBatchRenameUI = "showBatchRenameUI"
    case undoBatchRename = "undoBatchRename"
    case captureOCR = "captureOCR"
    case cutFiles = "cutFiles"
    case pasteFiles = "pasteFiles"
    case cancelCut = "cancelCut"
}

public struct IPCMessage: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let actionType: IPCActionType
    public let targetPaths: [String]
    
    public init(actionType: IPCActionType, targetPaths: [String] = []) {
        self.id = UUID()
        self.timestamp = Date()
        self.actionType = actionType
        self.targetPaths = targetPaths
    }
}

public final class IPCHelper: Sendable {
    public static let shared = IPCHelper()
    public static let distributedNotificationName = NSNotification.Name("com.sfinder.ipc.action")
    
    private init() {}
    
    public func send(message: IPCMessage) throws {
        let encoder = JSONEncoder()
        
        // 1. Primary: Custom URL Scheme via NSWorkspace (100% allowed across sandbox boundary)
        if let data = try? encoder.encode(message) {
            let base64 = data.base64EncodedString()
            let customAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~")
            let encodedQuery = base64.addingPercentEncoding(withAllowedCharacters: customAllowed) ?? base64
            if let url = URL(string: "sfinder://action?data=\(encodedQuery)") {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        
        // 2. Secondary fallback: DistributedNotificationCenter
        if let data = try? encoder.encode(message),
           let jsonStr = String(data: data, encoding: .utf8) {
            DistributedNotificationCenter.default().postNotificationName(
                Self.distributedNotificationName,
                object: nil,
                userInfo: ["payload": jsonStr],
                deliverImmediately: true
            )
        }
    }
}
