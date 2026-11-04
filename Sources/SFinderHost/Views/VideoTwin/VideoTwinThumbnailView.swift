import SwiftUI
import AVFoundation
import SFinderCore

/// Memory-bounded thumbnail cache for VideoTwin (max 24MB RAM).
public actor VideoTwinThumbnailCache {
    public static let shared = VideoTwinThumbnailCache()
    
    private var cache: [String: CGImage] = [:]
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    private var order: [String] = []
    private var cachedBytes = 0
    private let memoryBudget = 24 * 1024 * 1024 // 24MB
    
    public init() {}
    
    public func image(for url: URL, time: Double = 1.0) async -> CGImage? {
        let key = "\(url.path):\(time)"
        if let existing = cache[key] { return existing }
        
        // Deduplicate in-flight generation tasks
        if let running = inFlight[key] {
            return await running.value
        }
        
        let task = Task<CGImage?, Never> {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 100) // Optimal 2x Retina for ~72x46 display, 4x faster and lighter
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            
            guard let result = try? await generator.image(at: CMTime(seconds: max(0, time), preferredTimescale: 600)) else {
                return nil
            }
            return result.image
        }
        
        inFlight[key] = task
        let cgImage = await task.value
        inFlight.removeValue(forKey: key)
        
        if let cgImage {
            cache[key] = cgImage
            cachedBytes += cgImage.bytesPerRow * cgImage.height
            order.append(key)
            
            while order.count > 100 || cachedBytes > memoryBudget {
                if !order.isEmpty {
                    let evictKey = order.removeFirst()
                    if let evicted = cache.removeValue(forKey: evictKey) {
                        cachedBytes -= evicted.bytesPerRow * evicted.height
                    }
                }
            }
        }
        
        return cgImage
    }
    
    public func clear() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        cache.removeAll()
        order.removeAll()
        cachedBytes = 0
    }
}

public struct VideoTwinThumbnailView: View {
    public let url: URL
    public var time: Double = 1.0
    public var width: CGFloat = 84
    public var height: CGFloat = 56
    
    @State private var image: NSImage?
    @State private var isLoading = true
    
    public init(url: URL, time: Double = 1.0, width: CGFloat = 84, height: CGFloat = 56) {
        self.url = url
        self.time = time
        self.width = width
        self.height = height
    }
    
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.4))
            
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(CFinderTheme.primaryLight)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 18))
                    .foregroundStyle(CFinderTheme.textMuted)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CFinderTheme.cardBorder, lineWidth: 1)
        )
        .task(id: url.path) {
            isLoading = true
            if let cgImage = await VideoTwinThumbnailCache.shared.image(for: url, time: time) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            isLoading = false
        }
    }
}
