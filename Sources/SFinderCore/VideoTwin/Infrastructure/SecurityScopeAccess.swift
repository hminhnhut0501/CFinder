import Foundation

@MainActor
public final class SecurityScopeAccess {
    private var urls: [URL] = []
    public init() {
        for bookmark in UserDefaults.standard.array(forKey: "sfinder_scanBookmarks") as? [Data] ?? [] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() { urls.append(url) }
        }
    }
    public func close() { urls.forEach { $0.stopAccessingSecurityScopedResource() }; urls = [] }
}
