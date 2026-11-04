import Foundation

public enum CaseTransform: String, CaseIterable, Codable, Sendable {
    case none = "Không đổi"
    case lower = "viết thường (lower)"
    case upper = "VIẾT HOA (UPPER)"
    case title = "Viết Hoa Từng Từ (Title Case)"
    case sentence = "Viết hoa đầu câu (Sentence)"
    case camelCase = "camelCase"
    case snakeCase = "snake_case"
    case kebabCase = "kebab-case"
}

public enum NumberingPosition: String, CaseIterable, Codable, Sendable {
    case prefix = "Đầu tên"
    case suffix = "Cuối tên (trước đuôi .ext)"
    case replace = "Thay thế toàn bộ tên"
}

public enum NumberingFormat: String, CaseIterable, Codable, Sendable {
    case plain = "1, 2, 3..."
    case twoDigits = "01, 02, 03..."
    case threeDigits = "001, 002, 003..."
    case fourDigits = "0001, 0002..."
    case parentheses = "(1), (2), (3)..."
    case brackets = "[1], [2], [3]..."
}

public enum ExtensionTransform: String, CaseIterable, Codable, Sendable {
    case keep = "Giữ nguyên đuôi tệp"
    case lowercase = "Đuôi viết thường (.jpg)"
    case uppercase = "Đuôi viết HOA (.JPG)"
    case custom = "Đổi sang đuôi mới..."
}

public struct RenameRule: Codable, Equatable, Sendable {
    // 0. Reset / Xóa sạch ký tự tên gốc
    public var clearOriginalName: Bool = false // Xóa hết toàn bộ ký tự tên gốc để bắt đầu từ đầu
    public var customBaseName: String = ""     // Tên mới cơ sở (tuỳ chọn)
    
    // 1. Sequence numbering (Ưu tiên hàng đầu)
    public var enableNumbering: Bool = true
    public var numberingFormat: NumberingFormat = .twoDigits
    public var numberingPosition: NumberingPosition = .suffix
    public var startNumber: Int = 1
    public var step: Int = 1
    public var numberingSeparator: String = "_"
    
    // 2. Add / Insert text (Thêm text trước / sau)
    public var enablePrefixSuffix: Bool = false
    public var prefix: String = ""
    public var suffix: String = ""
    
    // 3. Find & Replace
    public var enableFindReplace: Bool = true
    public var findText: String = ""
    public var replaceText: String = ""
    public var isRegex: Bool = false
    public var matchCase: Bool = false
    
    // Case transformation
    public var caseTransform: CaseTransform = .none
    
    // Extension transformation
    public var extensionTransform: ExtensionTransform = .keep
    public var customExtension: String = ""
    
    // Cleanups & Normalizations
    public var removeAccents: Bool = false // Bỏ dấu tiếng Việt (Hàng Cú -> Hang Cu)
    public var replaceSpacesWithDash: Bool = false // Khoảng trắng -> Dấu gạch ngang (-)
    public var replaceSpacesWithUnderscore: Bool = false // Khoảng trắng -> Dấu gạch dưới (_)
    public var trimSpaces: Bool = true // Xóa khoảng trắng đầu & cuối
    
    public init() {}
}

extension RenameRule {
    private static let userDefaultsKey = "com.sfinder.lastRenameRule"
    private static let lastTabKey = "com.sfinder.lastSelectedTab"
    
    public static func loadLastUsed() -> RenameRule {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let rule = try? JSONDecoder().decode(RenameRule.self, from: data) {
            return rule
        }
        return RenameRule()
    }
    
    public func saveAsLastUsed() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }
    
    public static func loadLastTab() -> String? {
        UserDefaults.standard.string(forKey: lastTabKey)
    }
    
    public static func saveLastTab(_ tabId: String) {
        UserDefaults.standard.set(tabId, forKey: lastTabKey)
    }
    
    public static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: lastTabKey)
    }
}
