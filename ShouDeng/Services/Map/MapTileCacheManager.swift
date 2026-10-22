import Foundation
import MapKit

// MARK: - Map Tile Cache Manager
//
// Offline map tile caching for MKMapView using MKTileOverlay.
// Inspired by MapCache (merlos/MapCache): LRU disk cache with
// configurable max size. Tiles are stored in app's Caches directory
// so iOS can reclaim space under storage pressure.
//
// Usage:
//   let cache = MapTileCacheManager()
//   mapView.addOverlay(cache.tileOverlay, level: .aboveLabels)
//   mapView.delegate handles renderer creation via cache.renderer(for:)

final class MapTileCacheManager {

    // MARK: - Configuration

    struct Config {
        var maxCacheSizeMB: Int = 200          // 200 MB default
        var tileSize: Int = 256
        var minimumZ: Int = 1
        var maximumZ: Int = 19
        /// OpenStreetMap tile URL template. {z}/{x}/{y} are replaced by MKTileOverlay.
        var urlTemplate: String = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    }

    // MARK: - Properties

    private let config: Config
    private let cacheDirectory: URL
    private let queue = DispatchQueue(label: "com.shoudeng.tilecache", qos: .utility)
    private var currentCacheSizeBytes: Int64 = 0

    /// The tile overlay to add to your MKMapView
    let tileOverlay: CachedTileOverlay

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("map_tiles", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        tileOverlay = CachedTileOverlay(
            urlTemplate: config.urlTemplate,
            cacheDirectory: cacheDirectory,
            maxCacheSizeBytes: Int64(config.maxCacheSizeMB) * 1024 * 1024
        )
        tileOverlay.tileSize = CGSize(width: config.tileSize, height: config.tileSize)
        tileOverlay.minimumZ = config.minimumZ
        tileOverlay.maximumZ = config.maximumZ
        tileOverlay.canReplaceMapContent = false

        queue.async { [weak self] in
            self?.calculateCurrentCacheSize()
        }
    }

    /// Create renderer for the cached tile overlay.
    /// Call this from your MKMapViewDelegate's rendererForOverlay method.
    func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        guard overlay is CachedTileOverlay else { return nil }
        return MKTileOverlayRenderer(tileOverlay: tileOverlay)
    }

    /// Pre-cache tiles for a region at specified zoom levels.
    /// Useful for "download this area" feature.
    func prefetchTiles(region: MKCoordinateRegion, zoomLevels: ClosedRange<Int> = 10...15, progress: ((Double) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }

            var totalTiles = 0
            var fetchedTiles = 0

            // Calculate tile ranges for each zoom level
            var tileRequests: [(z: Int, x: Int, y: Int)] = []
            for z in zoomLevels {
                let minTile = self.tileCoordinate(for: CLLocationCoordinate2D(
                    latitude: region.center.latitude + region.span.latitudeDelta / 2,
                    longitude: region.center.longitude - region.span.longitudeDelta / 2
                ), zoom: z)
                let maxTile = self.tileCoordinate(for: CLLocationCoordinate2D(
                    latitude: region.center.latitude - region.span.latitudeDelta / 2,
                    longitude: region.center.longitude + region.span.longitudeDelta / 2
                ), zoom: z)

                for x in minTile.x...maxTile.x {
                    for y in minTile.y...maxTile.y {
                        tileRequests.append((z: z, x: x, y: y))
                    }
                }
            }

            totalTiles = tileRequests.count
            guard totalTiles > 0 else {
                DispatchQueue.main.async { progress?(1.0) }
                return
            }

            // Cap at 2000 tiles to prevent abuse
            let capped = Array(tileRequests.prefix(2000))

            let semaphore = DispatchSemaphore(value: 4) // 4 concurrent downloads
            let group = DispatchGroup()

            for tile in capped {
                group.enter()
                semaphore.wait()

                let cacheFile = self.cacheDirectory.appendingPathComponent("\(tile.z)/\(tile.x)/\(tile.y).png")

                if FileManager.default.fileExists(atPath: cacheFile.path) {
                    fetchedTiles += 1
                    DispatchQueue.main.async { progress?(Double(fetchedTiles) / Double(totalTiles)) }
                    semaphore.signal()
                    group.leave()
                    continue
                }

                let urlStr = self.config.urlTemplate
                    .replacingOccurrences(of: "{z}", with: "\(tile.z)")
                    .replacingOccurrences(of: "{x}", with: "\(tile.x)")
                    .replacingOccurrences(of: "{y}", with: "\(tile.y)")
                guard let url = URL(string: urlStr) else {
                    semaphore.signal()
                    group.leave()
                    continue
                }

                URLSession.shared.dataTask(with: url) { data, _, _ in
                    defer {
                        semaphore.signal()
                        group.leave()
                    }
                    guard let data else { return }
                    let dir = cacheFile.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? data.write(to: cacheFile)

                    fetchedTiles += 1
                    DispatchQueue.main.async { progress?(Double(fetchedTiles) / Double(totalTiles)) }
                }.resume()
            }

            group.wait()
        }
    }

    /// Clear all cached tiles
    func clearCache() {
        queue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: self.cacheDirectory)
            try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
            self.currentCacheSizeBytes = 0
        }
    }

    /// Current cache size in MB
    var cacheSizeMB: Double {
        Double(currentCacheSizeBytes) / (1024 * 1024)
    }

    // MARK: - Private

    private func tileCoordinate(for coordinate: CLLocationCoordinate2D, zoom: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(zoom))
        let x = Int(floor((coordinate.longitude + 180.0) / 360.0 * n))
        let latRad = coordinate.latitude * .pi / 180.0
        let y = Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))
        return (x: max(0, min(Int(n) - 1, x)), y: max(0, min(Int(n) - 1, y)))
    }

    private func calculateCurrentCacheSize() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        currentCacheSizeBytes = total
    }
}

// MARK: - Cached Tile Overlay

/// Custom MKTileOverlay that checks disk cache before downloading.
final class CachedTileOverlay: MKTileOverlay {

    private let cacheDirectory: URL
    private let maxCacheSizeBytes: Int64
    private let cacheQueue = DispatchQueue(label: "com.shoudeng.tileoverlay.cache", qos: .utility)

    init(urlTemplate: String?, cacheDirectory: URL, maxCacheSizeBytes: Int64) {
        self.cacheDirectory = cacheDirectory
        self.maxCacheSizeBytes = maxCacheSizeBytes
        super.init(urlTemplate: urlTemplate)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let cacheFile = cacheDirectory.appendingPathComponent("\(path.z)/\(path.x)/\(path.y).png")

        // Check cache first
        if let cachedData = try? Data(contentsOf: cacheFile) {
            // Touch file to update LRU timestamp
            cacheQueue.async {
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()],
                    ofItemAtPath: cacheFile.path
                )
            }
            result(cachedData, nil)
            return
        }

        // Download and cache
        super.loadTile(at: path) { [weak self] data, error in
            if let data, error == nil {
                self?.cacheQueue.async {
                    let dir = cacheFile.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? data.write(to: cacheFile)
                    self?.evictIfNeeded()
                }
            }
            result(data, error)
        }
    }

    /// LRU eviction: remove oldest tiles when cache exceeds max size
    private func evictIfNeeded() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var files: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate else { continue }
            files.append((url: fileURL, size: Int64(size), date: date))
            totalSize += Int64(size)
        }

        guard totalSize > maxCacheSizeBytes else { return }

        // Sort by date ascending (oldest first)
        files.sort { $0.date < $1.date }

        // Remove oldest until under 80% of max
        let targetSize = Int64(Double(maxCacheSizeBytes) * 0.8)
        for file in files {
            guard totalSize > targetSize else { break }
            try? fm.removeItem(at: file.url)
            totalSize -= file.size
        }
    }
}
