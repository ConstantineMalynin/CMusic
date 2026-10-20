//
//  ArtworkLoader.swift
//  CMusic
//

import AppKit
import ImageIO
import MusicKit

/// Downloads, decodes and caches artwork bitmaps so scrolling never waits on the network or the decoder twice.
///
/// Requested sizes are snapped to a few buckets, so a tile that changes width slightly (e.g. a grid
/// during window resize) keeps hitting the same cached image instead of requesting a new URL.
///
/// Main-actor isolated so `inFlight` and the cache lookups never race; downloads and decoding run off the main thread.
@MainActor
final class ArtworkLoader {
    static let shared = ArtworkLoader()

    private nonisolated static let buckets = [64, 128, 256, 384, 512, 768, 1024, 1536]

    private let memory = NSCache<NSURL, CGImage>()
    private var inFlight: [URL: Task<CGImage?, Never>] = [:]
    private let session: URLSession

    private init() {
        memory.totalCostLimit = 256 * 1024 * 1024

        // Artwork CDN responses are long-lived, so a disk cache makes the next launch instant too.
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Artwork", directoryHint: .isDirectory)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 512 * 1024 * 1024, directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    nonisolated static func pixelSize(forPoints points: CGFloat, scale: CGFloat) -> Int {
        let pixels = points * scale
        return buckets.first { CGFloat($0) >= pixels } ?? buckets[buckets.count - 1]
    }

    /// A remote URL for the artwork, or nil for artwork only MusicKit can render (e.g. `musicKit://` library art).
    nonisolated static func url(for artwork: Artwork, pixelSize: Int) -> URL? {
        guard let url = artwork.url(width: pixelSize, height: pixelSize),
              url.scheme == "https" || url.scheme == "http"
        else { return nil }
        return url
    }

    /// An already-decoded image at this size or larger, for showing artwork without a placeholder flash.
    func cachedImage(for artwork: Artwork, pixelSize: Int) -> CGImage? {
        // The exact bucket is the common hit, and it is checked before any larger ones are even formatted.
        guard let exact = Self.url(for: artwork, pixelSize: pixelSize) else { return nil }
        if let image = memory.object(forKey: exact as NSURL) { return image }
        for size in Self.buckets where size > pixelSize {
            if let url = Self.url(for: artwork, pixelSize: size), let image = memory.object(forKey: url as NSURL) {
                return image
            }
        }
        return nil
    }

    func image(for artwork: Artwork, pixelSize: Int) async -> CGImage? {
        guard let url = Self.url(for: artwork, pixelSize: pixelSize) else { return nil }
        if let image = memory.object(forKey: url as NSURL) { return image }
        if let task = inFlight[url] { return await task.value }

        // Not tied to the caller: a tile scrolling away shouldn't throw away a nearly finished download.
        let task = Task { [session] () -> CGImage? in
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return await Task.detached(priority: .userInitiated) {
                Self.decode(data, maxPixelSize: pixelSize)
            }.value
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            memory.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        }
        return image
    }

    /// Warms the cache for content that is likely to be shown next.
    func prefetch(_ artworks: some Sequence<Artwork?>, points: CGFloat) {
        let pixelSize = Self.pixelSize(forPoints: points, scale: NSScreen.main?.backingScaleFactor ?? 2)
        for artwork in artworks.compactMap(\.self) {
            Task(priority: .utility) { _ = await image(for: artwork, pixelSize: pixelSize) }
        }
    }

    /// Decodes straight to display size, so the main thread never inflates a full-size JPEG.
    private nonisolated static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
