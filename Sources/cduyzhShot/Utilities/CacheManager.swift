import AppKit

public final class CacheManager {
    public static let shared = CacheManager()

    public let cacheDirectory: URL

    private let fileManager = FileManager.default

    private init() {
        let baseCache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = baseCache.appendingPathComponent("com.cduyzh.shot", isDirectory: true)

        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: cacheDirectory.appendingPathComponent("Screenshots"), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: cacheDirectory.appendingPathComponent("Recordings"), withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: cacheDirectory.appendingPathComponent("Stitches"), withIntermediateDirectories: true)
    }

    /// Saves a temporary PNG to the cache directory and returns its URL.
    public func saveTemporaryImage(_ image: CGImage, prefix: String = "clip") -> URL? {
        createDirectoriesIfNeeded()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let filename = "\(prefix)_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6)).png"
        let fileURL = cacheDirectory.appendingPathComponent("Screenshots").appendingPathComponent(filename)

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("[CacheManager] Error saving temporary image: \(error)")
            return nil
        }
    }

    /// Calculates total cache size in bytes.
    public func getCacheSizeBytes() -> Int64 {
        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory, !isDirectory,
                  let size = resourceValues.fileSize else {
                continue
            }
            totalSize += Int64(size)
        }
        return totalSize
    }

    /// Returns human-readable cache size string (e.g. "12.4 MB")
    public func formattedCacheSize() -> String {
        let bytes = getCacheSizeBytes()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Clears all files in the cache directory.
    public func clearAllCache() {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for url in contents {
            try? fileManager.removeItem(at: url)
        }

        createDirectoriesIfNeeded()
    }

    /// Removes files older than the specified number of days.
    public func cleanExpiredCache(olderThanDays days: Int) {
        guard days > 0 else { return }
        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 3600))

        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]) else {
            return
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory, !isDirectory,
                  let modDate = resourceValues.contentModificationDate else {
                continue
            }

            if modDate < cutoffDate {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    /// Checks if cache exceeds the maximum allowed size (in MB), and deletes oldest files first until below limit.
    public func pruneCacheIfExceeds(maxSizeMB: Int) {
        let maxBytes = Int64(maxSizeMB) * 1024 * 1024
        var currentBytes = getCacheSizeBytes()
        guard currentBytes > maxBytes else { return }

        guard let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]) else {
            return
        }

        var files: [(url: URL, date: Date, size: Int64)] = []
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]),
                  let isDir = vals.isDirectory, !isDir,
                  let date = vals.contentModificationDate,
                  let size = vals.fileSize else {
                continue
            }
            files.append((url: fileURL, date: date, size: Int64(size)))
        }

        // Sort oldest first
        files.sort { $0.date < $1.date }

        for file in files {
            if currentBytes <= maxBytes { break }
            try? fileManager.removeItem(at: file.url)
            currentBytes -= file.size
        }
    }

    /// Executes scheduled cleanup based on user preferences.
    public func performScheduledCleanup() {
        let prefs = UserPreferences.shared
        guard prefs.autoCleanCacheEnabled else { return }

        // Clean files older than configured retention days (default 7 days)
        cleanExpiredCache(olderThanDays: prefs.cacheRetentionDays)

        // Prune if exceeds max cache size (default 500 MB)
        pruneCacheIfExceeds(maxSizeMB: prefs.maxCacheSizeMB)
    }
}
