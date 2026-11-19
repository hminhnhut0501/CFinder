import Foundation
import AppKit

// MARK: - Disk Streaming Scanner (Zero-RAM Overhead Iterator)

/// Quét kích thước thư mục và dọn dẹp theo cơ chế Stream/Accumulator.
///
/// Tuyệt đối không gom hàng trăm nghìn URL vào mảng bộ nhớ (tránh spike RAM như CleanMyMac),
/// chỉ tích lũy `totalSizeBytes` và `fileCount` trực tiếp trong vòng lặp.
public final class DiskStreamingScanner: Sendable {
    public static let shared = DiskStreamingScanner()

    private init() {}

    /// Tính tổng dung lượng (bytes) và số file của một thư mục.
    public func measureDirectory(at url: URL, maxDepth: Int = 10) -> (bytes: Int64, count: Int) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return (0, 0)
        }

        if !isDir.boolValue {
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return (size, 1)
        }

        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isPackageKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return (0, 0)
        }

        var totalBytes: Int64 = 0
        var totalCount: Int = 0

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }
            if resourceValues.isDirectory == true && resourceValues.isPackage != true {
                continue
            }
            if let size = resourceValues.fileSize {
                totalBytes += Int64(size)
                totalCount += 1
            }
        }

        return (totalBytes, totalCount)
    }

    /// Dọn dẹp an toàn các tệp con bên trong thư mục (giữ lại thư mục gốc).
    @discardableResult
    public func cleanContents(of directoryURL: URL) -> Int64 {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var freedBytes: Int64 = 0
        for item in contents {
            let (itemBytes, _) = measureDirectory(at: item)
            do {
                try fm.removeItem(at: item)
                freedBytes += itemBytes
            } catch {
                // Thử recycle vào thùng rác nếu removeItem bị khóa
                _ = try? fm.trashItem(at: item, resultingItemURL: nil)
            }
        }
        return freedBytes
    }

    /// Đưa tệp / thư mục vào Thùng rác một cách an toàn (người dùng có thể khôi phục).
    public func recycleItem(at url: URL) -> Bool {
        var result = false
        let sema = DispatchSemaphore(value: 0)
        NSWorkspace.shared.recycle([url]) { _, error in
            result = (error == nil)
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 3.0)
        return result
    }
}
