import Foundation
import AppKit
import Combine

// MARK: - System Cleaner Manager (CleanMyMac & AppCleaner Replacement)

/// Bộ điều phối trung tâm Dọn rác hệ thống & Gỡ cài đặt ứng dụng tận gốc.
///
/// Quản lý 3 trụ cột:
/// 1. Dọn dẹp rác (Caches, Logs, Xcode DerivedData, System Trash).
/// 2. Gỡ cài đặt ứng dụng (Quét danh sách `.app`, phân tích tệp thừa leftovers và xóa an toàn).
/// 3. Quét tệp tin lớn (Large Files Finder) để giải phóng dung lượng SSD cấp tốc.
@MainActor
public final class SystemCleanerManager: ObservableObject {
    public static let shared = SystemCleanerManager()

    // MARK: - Navigation State (0: Dọn rác, 1: Gỡ App, 2: Tệp lớn)
    @Published public var selectedSection: Int = 0

    // MARK: - Junk Cleaner State
    @Published public var junkCategories: [JunkCategoryItem] = []
    @Published public var isScanningJunk: Bool = false
    @Published public var isCleaningJunk: Bool = false
    @Published public var totalJunkBytes: Int64 = 0
    @Published public var lastCleanedBytes: Int64 = 0

    // MARK: - App Uninstaller State
    @Published public var installedApps: [InstalledAppItem] = []
    @Published public var isScanningApps: Bool = false
    @Published public var selectedApp: InstalledAppItem?
    @Published public var isUninstalling: Bool = false
    @Published public var appSearchQuery: String = ""

    // MARK: - Large Files State
    @Published public var largeFiles: [LargeFileItem] = []
    @Published public var isScanningLargeFiles: Bool = false

    private init() {
        setupDefaultCategories()
    }

    // MARK: - Setup Categories

    private func setupDefaultCategories() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")

        self.junkCategories = [
            JunkCategoryItem(
                id: "caches",
                title: "Bộ nhớ đệm ứng dụng & web",
                subtitle: "Cache trình duyệt, Spotify, Zalo, Telegram, Adobe...",
                icon: "internaldrive",
                iconColorHex: "0EA5E9",
                directoryURLs: [
                    library.appendingPathComponent("Caches"),
                    library.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Caches")
                ]
            ),
            JunkCategoryItem(
                id: "logs",
                title: "Nhật ký & Báo cáo sự cố",
                subtitle: "Các tệp .log, .crash tích tụ lâu ngày không cần thiết",
                icon: "doc.text.magnifyingglass",
                iconColorHex: "F59E0B",
                directoryURLs: [
                    library.appendingPathComponent("Logs"),
                    URL(fileURLWithPath: "/Library/Logs")
                ]
            ),
            JunkCategoryItem(
                id: "developer",
                title: "Dữ liệu rác lập trình viên (Xcode)",
                subtitle: "DerivedData, Module cache và bộ nhớ build tạm",
                icon: "hammer.fill",
                iconColorHex: "8B5CF6",
                directoryURLs: [
                    library.appendingPathComponent("Developer/Xcode/DerivedData"),
                    library.appendingPathComponent("Developer/Xcode/Archives")
                ]
            ),
            JunkCategoryItem(
                id: "trash",
                title: "Thùng rác hệ thống (Trash)",
                subtitle: "Các tệp đang nằm chờ dọn dẹp trong Thùng rác",
                icon: "trash.fill",
                iconColorHex: "EF4444",
                directoryURLs: [
                    home.appendingPathComponent(".Trash")
                ]
            )
        ]
    }

    // MARK: - 1. Junk Cleaning Logic

    public func scanJunk() {
        guard !isScanningJunk else { return }
        isScanningJunk = true

        Task.detached(priority: .userInitiated) {
            var updatedCategories = await self.junkCategories

            for i in 0..<updatedCategories.count {
                var catBytes: Int64 = 0
                var catCount: Int = 0
                for dir in updatedCategories[i].directoryURLs {
                    let (b, c) = DiskStreamingScanner.shared.measureDirectory(at: dir)
                    catBytes += b
                    catCount += c
                }
                updatedCategories[i].sizeBytes = catBytes
                updatedCategories[i].fileCount = catCount
            }

            let total = updatedCategories.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }

            await MainActor.run {
                self.junkCategories = updatedCategories
                self.totalJunkBytes = total
                self.isScanningJunk = false
            }
        }
    }

    public func cleanSelectedJunk() {
        guard !isCleaningJunk else { return }
        isCleaningJunk = true

        Task.detached(priority: .userInitiated) {
            let categories = await self.junkCategories.filter(\.isSelected)
            var totalFreed: Int64 = 0

            for cat in categories {
                if cat.id == "trash" {
                    // Xóa thùng rác an toàn qua Finder AppleScript
                    let script = "tell application \"Finder\" to empty trash"
                    _ = try? NSAppleScript(source: script)?.executeAndReturnError(nil)
                    totalFreed += cat.sizeBytes
                } else {
                    for dir in cat.directoryURLs {
                        let freed = DiskStreamingScanner.shared.cleanContents(of: dir)
                        totalFreed += freed
                    }
                }
            }

            await MainActor.run {
                self.lastCleanedBytes = totalFreed
                self.isCleaningJunk = false
                self.scanJunk()
            }
        }
    }

    // MARK: - 2. App Uninstaller Logic (AppCleaner)

    public func scanInstalledApps() {
        guard !isScanningApps else { return }
        isScanningApps = true

        Task.detached(priority: .userInitiated) {
            let searchDirs = [
                URL(fileURLWithPath: "/Applications"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            ]

            var apps: [InstalledAppItem] = []
            let fm = FileManager.default

            for dir in searchDirs {
                guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
                    continue
                }

                for item in contents where item.pathExtension == "app" {
                    guard let info = AppLeftoverResolver.shared.resolveAppInfo(at: item) else {
                        continue
                    }
                    let (appBytes, _) = DiskStreamingScanner.shared.measureDirectory(at: item)
                    apps.append(InstalledAppItem(
                        name: info.name,
                        bundleIdentifier: info.bundleId,
                        bundleURL: item,
                        appSizeBytes: appBytes
                    ))
                }
            }

            apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            await MainActor.run {
                self.installedApps = apps
                self.isScanningApps = false
            }
        }
    }

    public func inspectApp(_ app: InstalledAppItem) {
        Task.detached(priority: .userInitiated) {
            let leftovers = AppLeftoverResolver.shared.findLeftovers(
                bundleId: app.bundleIdentifier,
                appName: app.name
            )

            await MainActor.run {
                var updated = app
                updated.leftovers = leftovers
                updated.isInspected = true
                self.selectedApp = updated

                if let idx = self.installedApps.firstIndex(where: { $0.id == app.id }) {
                    self.installedApps[idx] = updated
                }
            }
        }
    }

    /// Kéo thả tệp `.app` từ ngoài vào để phân tích và chuẩn bị gỡ bỏ
    public func inspectExternalApp(at bundleURL: URL) {
        guard bundleURL.pathExtension == "app",
              let info = AppLeftoverResolver.shared.resolveAppInfo(at: bundleURL) else {
            return
        }

        Task.detached(priority: .userInitiated) {
            let (appBytes, _) = DiskStreamingScanner.shared.measureDirectory(at: bundleURL)
            let leftovers = AppLeftoverResolver.shared.findLeftovers(
                bundleId: info.bundleId,
                appName: info.name
            )

            let appItem = InstalledAppItem(
                name: info.name,
                bundleIdentifier: info.bundleId,
                bundleURL: bundleURL,
                appSizeBytes: appBytes,
                leftovers: leftovers,
                isInspected: true
            )

            await MainActor.run {
                self.selectedSection = 1 // Chuyển sang tab Gỡ App
                self.selectedApp = appItem
            }
        }
    }

    public func uninstallSelectedApp() {
        guard let app = selectedApp, !isUninstalling else { return }
        isUninstalling = true

        Task.detached(priority: .userInitiated) {
            // 1. Chuyển các tệp thừa (leftovers) được chọn vào Thùng rác
            let selectedLeftovers = app.leftovers.filter(\.isSelected)
            for item in selectedLeftovers {
                _ = DiskStreamingScanner.shared.recycleItem(at: item.url)
            }

            // 2. Chuyển tệp bundle `.app` vào Thùng rác
            _ = DiskStreamingScanner.shared.recycleItem(at: app.bundleURL)

            await MainActor.run {
                self.isUninstalling = false
                self.selectedApp = nil
                self.scanInstalledApps()
            }
        }
    }

    // MARK: - 3. Large Files Finder Logic

    public func scanLargeFiles(minSizeMB: Int = 150) {
        guard !isScanningLargeFiles else { return }
        isScanningLargeFiles = true

        Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let scanFolders = [
                home.appendingPathComponent("Downloads"),
                home.appendingPathComponent("Documents"),
                home.appendingPathComponent("Movies"),
                home.appendingPathComponent("Desktop")
            ]

            let thresholdBytes = Int64(minSizeMB) * 1024 * 1024
            var found: [LargeFileItem] = []
            let fm = FileManager.default

            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isPackageKey]

            for folder in scanFolders {
                guard let enumerator = fm.enumerator(
                    at: folder,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: nil
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    guard let res = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
                    if res.isDirectory == true && res.isPackage != true { continue }

                    if let sz = res.fileSize, Int64(sz) >= thresholdBytes {
                        found.append(LargeFileItem(
                            name: fileURL.lastPathComponent,
                            url: fileURL,
                            sizeBytes: Int64(sz),
                            fileExtension: fileURL.pathExtension.uppercased(),
                            modifiedDate: res.contentModificationDate ?? Date()
                        ))
                    }
                }
            }

            found.sort { $0.sizeBytes > $1.sizeBytes }

            await MainActor.run {
                self.largeFiles = found
                self.isScanningLargeFiles = false
            }
        }
    }

    /// Giải phóng bộ nhớ tạm khi người dùng rời khỏi màn hình Dọn dẹp
    public func releaseScanCache() {
        self.largeFiles = []
        for i in 0..<installedApps.count {
            if installedApps[i].id != selectedApp?.id {
                installedApps[i].leftovers = []
                installedApps[i].isInspected = false
            }
        }
    }

    public func recycleLargeFile(_ item: LargeFileItem) {
        Task.detached(priority: .userInitiated) {
            _ = DiskStreamingScanner.shared.recycleItem(at: item.url)
            await MainActor.run {
                self.largeFiles.removeAll(where: { $0.id == item.id })
            }
        }
    }
}
