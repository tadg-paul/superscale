// ABOUTME: Holds renderings already produced, keyed by what produced them, so toggling is free.
// ABOUTME: Bounded at four entries, with the picture currently on the canvas exempt from eviction.

import Foundation

/// What produced a rendering, and therefore when it may be reused.
///
/// A rendering is reusable exactly when all four match. That makes invalidation fall out of the key
/// rather than being managed: applying a filter mints a new asset identity, so its renderings
/// simply miss, and nothing that is still valid is ever discarded. The key is also what makes a
/// late arrival detectable — a rendering whose key no longer describes the current state is refused
/// rather than drawn over a picture it does not belong to.
public struct RenderingKey: Hashable, Sendable {
    public let assetID: String
    public let modelID: String
    public let sizing: String
    public let facesEnhanced: Bool

    public init(assetID: String, modelID: String, sizing: String, facesEnhanced: Bool) {
        self.assetID = assetID
        self.modelID = modelID
        self.sizing = sizing
        self.facesEnhanced = facesEnhanced
    }
}

/// Renderings already produced, so that turning something off and on again costs nothing.
///
/// Bounded by entry count rather than by bytes. Four is deliberate: it is exactly the
/// with-and-without-faces pair for the base and for the current candidate, which is the working set
/// of a session that is comparing. At eight megapixels each that is roughly 128 MB, recorded on the
/// master's residual risk and carried into the memory cap work rather than discovered there.
///
/// Not an actor. The store is main-actor state feeding a view, and making it an actor would put a
/// suspension point between deciding what to draw and drawing it.
@MainActor
public final class RenderingStore {

    /// Deep enough to hold the faces pair for the base and for the candidate.
    public static let bound = 4

    private var entries: [RenderingKey: RenderedImage] = [:]
    /// Least recently used first.
    private var recency: [RenderingKey] = []
    private var displayed: RenderingKey?

    public init() {}

    public var count: Int { entries.count }

    /// What is held for a key, without producing anything or disturbing recency.
    public func held(for key: RenderingKey) -> RenderedImage? {
        entries[key]
    }

    /// Names the rendering currently on the canvas, which eviction then leaves alone.
    public func markDisplayed(_ key: RenderingKey) {
        displayed = key
        touch(key)
    }

    /// Takes in a rendering that has already been produced elsewhere.
    ///
    /// The producer form below is the one to prefer, because it cannot forget to look first. This
    /// exists for a caller whose production is driven by something other than the call site — a
    /// Combine pipeline that publishes when a run completes, in this application's case.
    public func admit(_ image: RenderedImage, for key: RenderingKey) {
        entries[key] = image
        touch(key)
        evictIfNeeded()
    }

    /// The rendering for `key`, produced only if it is not already held.
    ///
    /// A producer that throws leaves the store untouched, so a failed operation contributes no
    /// rendering and the next ask tries again rather than serving a hole.
    public func rendering(
        for key: RenderingKey,
        producedBy produce: () async throws -> RenderedImage
    ) async rethrows -> RenderedImage {
        if let held = entries[key] {
            touch(key)
            return held
        }

        let produced = try await produce()
        entries[key] = produced
        touch(key)
        evictIfNeeded()
        return produced
    }

    /// Drops everything, for when the working picture is replaced outright.
    ///
    /// Not ordinarily needed — a new picture mints a new asset identity, so its renderings miss and
    /// the bound retires the old ones in due course. Used where the session genuinely restarts, so
    /// that memory does not carry a picture the user has moved on from until four more arrive.
    public func forget() {
        entries.removeAll()
        recency.removeAll()
        displayed = nil
    }

    private func touch(_ key: RenderingKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictIfNeeded() {
        while entries.count > Self.bound {
            guard let victim = recency.first(where: { $0 != displayed }) else { return }
            entries.removeValue(forKey: victim)
            recency.removeAll { $0 == victim }
        }
    }
}
