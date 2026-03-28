// ABOUTME: Caches compiled CoreML .mlmodelc bundles to avoid recompilation on every run.
// ABOUTME: Uses modification date of source .mlpackage as cache key for invalidation.

import CoreML
import Foundation

/// Manages a persistent cache of compiled CoreML models.
///
/// CoreML's `compileModel(at:)` translates `.mlpackage` source into a
/// device-optimized `.mlmodelc` bundle. This takes ~4 seconds per model.
/// By caching the compiled output, subsequent loads skip compilation
/// entirely (~200ms).
public enum ModelCache {

    /// Persistent cache directory for compiled models.
    public static var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("superscale")
            .appendingPathComponent("compiled")
    }

    /// Load a compiled model from cache, or compile and cache it.
    ///
    /// - Parameter sourceURL: Path to the `.mlpackage` directory.
    /// - Returns: URL of the compiled `.mlmodelc` bundle (either cached or freshly compiled).
    public static func loadCompiledModel(at sourceURL: URL) throws -> URL {
        let modelName = sourceURL.deletingPathExtension().lastPathComponent
        let cachedModelDir = cacheDirectory.appendingPathComponent("\(modelName).mlmodelc")
        let cacheKeyFile = cacheDirectory.appendingPathComponent("\(modelName).cachekey")

        let currentKey = cacheKey(for: sourceURL)

        // Check if cached version exists and key matches
        if FileManager.default.fileExists(atPath: cachedModelDir.path),
           let storedKey = try? String(contentsOf: cacheKeyFile, encoding: .utf8),
           storedKey == currentKey {
            return cachedModelDir
        }

        // Compile the model
        let compiledURL = try MLModel.compileModel(at: sourceURL)

        // Remove stale cache entry if present
        try? FileManager.default.removeItem(at: cachedModelDir)

        // Ensure cache directory exists
        try FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true)

        // Persist the compiled model and cache key
        try FileManager.default.copyItem(at: compiledURL, to: cachedModelDir)
        try currentKey.write(to: cacheKeyFile, atomically: true, encoding: .utf8)

        return cachedModelDir
    }

    /// Remove all cached compiled models.
    public static func clearCache() throws {
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    /// Derive a cache key from the source model's modification date.
    ///
    /// When the `.mlpackage` is updated (e.g. via `brew upgrade`), its
    /// modification date changes, invalidating the cache automatically.
    private static func cacheKey(for sourceURL: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
              let mdate = attrs[.modificationDate] as? Date else {
            return "unknown"
        }
        return String(mdate.timeIntervalSince1970)
    }
}
