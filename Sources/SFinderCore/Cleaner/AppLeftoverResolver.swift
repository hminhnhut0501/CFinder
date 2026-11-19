import Foundation

// MARK: - App Leftover Resolver (AppCleaner Heuristic Engine)

/// Tìm kiếm tệp thừa và dữ liệu cấu hình rải rác của một ứng dụng macOS dựa trên Bundle Identifier.
///
/// Quét trực tiếp các đường dẫn chuẩn theo chuẩn Apple sandbox & app layout,
/// cho kết quả tức thì (< 50ms) mà không phụ thuộc vào Spotlight indexing.
public final class AppLeftoverResolver: Sendable {
    public static let shared = AppLeftoverResolver()

    private init() {}

    /// Giải mã thông tin `CFBundleIdentifier` và `CFBundleName` từ tệp `Info.plist` của `.app`.
    public func resolveAppInfo(at bundleURL: URL) -> (bundleId: String, name: String)? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        let bundleId = plist["CFBundleIdentifier"] as? String ?? ""
        let name = (plist["CFBundleDisplayName"] as? String) ??
                   (plist["CFBundleName"] as? String) ??
                   bundleURL.deletingPathExtension().lastPathComponent
        return (bundleId, name)
    }

    /// Quét toàn bộ các tệp/thư mục rác liên quan đến ứng dụng trong Library.
    public func findLeftovers(bundleId: String, appName: String) -> [AppLeftoverItem] {
        var items: [AppLeftoverItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")

        // 1. Application Support
        checkAndAdd(
            category: "Application Support",
            url: library.appendingPathComponent("Application Support/\(bundleId)"),
            into: &items
        )
        if !appName.isEmpty && appName != bundleId {
            checkAndAdd(
                category: "Application Support",
                url: library.appendingPathComponent("Application Support/\(appName)"),
                into: &items
            )
        }

        // 2. Caches
        checkAndAdd(
            category: "Caches",
            url: library.appendingPathComponent("Caches/\(bundleId)"),
            into: &items
        )
        if !appName.isEmpty && appName != bundleId {
            checkAndAdd(
                category: "Caches",
                url: library.appendingPathComponent("Caches/\(appName)"),
                into: &items
            )
        }

        // 3. Containers (Sandbox)
        checkAndAdd(
            category: "Containers (Sandbox)",
            url: library.appendingPathComponent("Containers/\(bundleId)"),
            into: &items
        )

        // 4. Preferences
        checkAndAdd(
            category: "Preferences (Cấu hình)",
            url: library.appendingPathComponent("Preferences/\(bundleId).plist"),
            into: &items
        )

        // 5. Saved Application State
        checkAndAdd(
            category: "Saved Application State",
            url: library.appendingPathComponent("Saved Application State/\(bundleId).savedState"),
            into: &items
        )

        // 6. HTTPStorages & WebKit
        checkAndAdd(
            category: "HTTP Data Storage",
            url: library.appendingPathComponent("HTTPStorages/\(bundleId)"),
            into: &items
        )
        checkAndAdd(
            category: "WebKit Storage",
            url: library.appendingPathComponent("WebKit/\(bundleId)"),
            into: &items
        )

        // 7. LaunchAgents (Tự khởi động)
        checkAndAdd(
            category: "Launch Agent",
            url: library.appendingPathComponent("LaunchAgents/\(bundleId).plist"),
            into: &items
        )

        // 8. Logs
        checkAndAdd(
            category: "Logs",
            url: library.appendingPathComponent("Logs/\(appName)"),
            into: &items
        )
        if !bundleId.isEmpty && bundleId != appName {
            checkAndAdd(
                category: "Logs",
                url: library.appendingPathComponent("Logs/\(bundleId)"),
                into: &items
            )
        }

        return items
    }

    private func checkAndAdd(category: String, url: URL, into list: inout [AppLeftoverItem]) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }

        // Tránh trùng lặp
        if list.contains(where: { $0.url.path == url.path }) { return }

        let (bytes, _) = DiskStreamingScanner.shared.measureDirectory(at: url)
        list.append(AppLeftoverItem(categoryName: category, url: url, sizeBytes: bytes, isSelected: true))
    }
}
