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

public enum DatePrefixFormat: String, CaseIterable, Codable, Sendable {
    case yyMMdd_ = "YYMMDD_"
    case yyyyMMdd_ = "YYYYMMDD_"
    case yy_MM_dd_ = "YY_MM_DD_"
    case yyyy_MM_dd_ = "YYYY_MM_DD_"
    case yyMMdd = "YYMMDD"
    
    public func formatted(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        
        switch self {
        case .yyMMdd_:
            formatter.dateFormat = "yyMMdd"
            return "\(formatter.string(from: date))_"
        case .yyyyMMdd_:
            formatter.dateFormat = "yyyyMMdd"
            return "\(formatter.string(from: date))_"
        case .yy_MM_dd_:
            formatter.dateFormat = "yy_MM_dd"
            return "\(formatter.string(from: date))_"
        case .yyyy_MM_dd_:
            formatter.dateFormat = "yyyy_MM_dd"
            return "\(formatter.string(from: date))_"
        case .yyMMdd:
            formatter.dateFormat = "yyMMdd"
            return formatter.string(from: date)
        }
    }
    
    public func menuTitle(for date: Date = Date()) -> String {
        let sample = formatted(date: date)
        return "\(rawValue) (\(sample))"
    }
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
    
    // 2.3. Date Prefix (Thêm ngày định dạng YYMMDD_ trước tiên - Tự động lấy hôm nay)
    public var enableDatePrefix: Bool = false
    public var datePrefixFormat: DatePrefixFormat = .yyMMdd_
    
    public func effectiveDatePrefix(for date: Date = Date()) -> String {
        guard enableDatePrefix else { return "" }
        return datePrefixFormat.formatted(date: date)
    }
    
    // 2.5. Delete characters (Xóa x ký tự phía trước / sau)
    public var deleteFirstN: Int = 0 // Số ký tự xóa ở đầu tên
    public var deleteLastN: Int = 0  // Số ký tự xóa ở cuối tên
    
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
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clearOriginalName = try container.decodeIfPresent(Bool.self, forKey: .clearOriginalName) ?? false
        customBaseName = try container.decodeIfPresent(String.self, forKey: .customBaseName) ?? ""
        
        enableNumbering = try container.decodeIfPresent(Bool.self, forKey: .enableNumbering) ?? true
        numberingFormat = try container.decodeIfPresent(NumberingFormat.self, forKey: .numberingFormat) ?? .twoDigits
        numberingPosition = try container.decodeIfPresent(NumberingPosition.self, forKey: .numberingPosition) ?? .suffix
        startNumber = try container.decodeIfPresent(Int.self, forKey: .startNumber) ?? 1
        step = try container.decodeIfPresent(Int.self, forKey: .step) ?? 1
        numberingSeparator = try container.decodeIfPresent(String.self, forKey: .numberingSeparator) ?? "_"
        
        enablePrefixSuffix = try container.decodeIfPresent(Bool.self, forKey: .enablePrefixSuffix) ?? false
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        suffix = try container.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        
        enableDatePrefix = try container.decodeIfPresent(Bool.self, forKey: .enableDatePrefix) ?? false
        datePrefixFormat = try container.decodeIfPresent(DatePrefixFormat.self, forKey: .datePrefixFormat) ?? .yyMMdd_
        
        deleteFirstN = try container.decodeIfPresent(Int.self, forKey: .deleteFirstN) ?? 0
        deleteLastN = try container.decodeIfPresent(Int.self, forKey: .deleteLastN) ?? 0
        
        enableFindReplace = try container.decodeIfPresent(Bool.self, forKey: .enableFindReplace) ?? true
        findText = try container.decodeIfPresent(String.self, forKey: .findText) ?? ""
        replaceText = try container.decodeIfPresent(String.self, forKey: .replaceText) ?? ""
        isRegex = try container.decodeIfPresent(Bool.self, forKey: .isRegex) ?? false
        matchCase = try container.decodeIfPresent(Bool.self, forKey: .matchCase) ?? false
        
        caseTransform = try container.decodeIfPresent(CaseTransform.self, forKey: .caseTransform) ?? .none
        
        extensionTransform = try container.decodeIfPresent(ExtensionTransform.self, forKey: .extensionTransform) ?? .keep
        customExtension = try container.decodeIfPresent(String.self, forKey: .customExtension) ?? ""
        
        removeAccents = try container.decodeIfPresent(Bool.self, forKey: .removeAccents) ?? false
        replaceSpacesWithDash = try container.decodeIfPresent(Bool.self, forKey: .replaceSpacesWithDash) ?? false
        replaceSpacesWithUnderscore = try container.decodeIfPresent(Bool.self, forKey: .replaceSpacesWithUnderscore) ?? false
        trimSpaces = try container.decodeIfPresent(Bool.self, forKey: .trimSpaces) ?? true
    }
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
