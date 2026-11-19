import Foundation
import SwiftUI

// MARK: - Cleaner & App Uninstaller Models

public struct JunkCategoryItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let iconColorHex: String
    public var sizeBytes: Int64
    public var fileCount: Int
    public var isSelected: Bool
    public let directoryURLs: [URL]

    public init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        iconColorHex: String,
        sizeBytes: Int64 = 0,
        fileCount: Int = 0,
        isSelected: Bool = true,
        directoryURLs: [URL] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColorHex = iconColorHex
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
        self.isSelected = isSelected
        self.directoryURLs = directoryURLs
    }

    public var sizeFormatted: String {
        CleanerByteFormatter.format(sizeBytes)
    }

    public static func == (lhs: JunkCategoryItem, rhs: JunkCategoryItem) -> Bool {
        lhs.id == rhs.id && lhs.sizeBytes == rhs.sizeBytes && lhs.isSelected == rhs.isSelected && lhs.fileCount == rhs.fileCount
    }
}

public struct AppLeftoverItem: Identifiable, Equatable, Sendable {
    public let id: UUID = UUID()
    public let categoryName: String
    public let url: URL
    public let sizeBytes: Int64
    public var isSelected: Bool

    public init(categoryName: String, url: URL, sizeBytes: Int64, isSelected: Bool = true) {
        self.categoryName = categoryName
        self.url = url
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
    }

    public var sizeFormatted: String {
        CleanerByteFormatter.format(sizeBytes)
    }
}

public struct InstalledAppItem: Identifiable, Equatable, @unchecked Sendable {
    public var id: String { bundleURL.path }
    public let name: String
    public let bundleIdentifier: String
    public let bundleURL: URL
    public let appSizeBytes: Int64
    public var leftovers: [AppLeftoverItem]
    public var isInspected: Bool

    public init(
        name: String,
        bundleIdentifier: String,
        bundleURL: URL,
        appSizeBytes: Int64,
        leftovers: [AppLeftoverItem] = [],
        isInspected: Bool = false
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.appSizeBytes = appSizeBytes
        self.leftovers = leftovers
        self.isInspected = isInspected
    }

    public var totalSizeBytes: Int64 {
        appSizeBytes + leftovers.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalSizeFormatted: String {
        CleanerByteFormatter.format(totalSizeBytes)
    }

    public var appSizeFormatted: String {
        CleanerByteFormatter.format(appSizeBytes)
    }

    public var icon: NSImage {
        NSWorkspace.shared.icon(forFile: bundleURL.path)
    }

    public static func == (lhs: InstalledAppItem, rhs: InstalledAppItem) -> Bool {
        lhs.id == rhs.id && lhs.leftovers.count == rhs.leftovers.count && lhs.isInspected == rhs.isInspected
    }
}

public struct LargeFileItem: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let url: URL
    public let sizeBytes: Int64
    public let fileExtension: String
    public let modifiedDate: Date

    public init(name: String, url: URL, sizeBytes: Int64, fileExtension: String, modifiedDate: Date) {
        self.name = name
        self.url = url
        self.sizeBytes = sizeBytes
        self.fileExtension = fileExtension
        self.modifiedDate = modifiedDate
    }

    public var sizeFormatted: String {
        CleanerByteFormatter.format(sizeBytes)
    }
}

public enum CleanerByteFormatter {
    public static func format(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1_073_741_824.0 {
            return String(format: "%.1f GB", b / 1_073_741_824.0)
        } else if b >= 1_048_576.0 {
            return String(format: "%.1f MB", b / 1_048_576.0)
        } else if b >= 1024.0 {
            return String(format: "%.0f KB", b / 1024.0)
        } else {
            return "\(bytes) B"
        }
    }
}
