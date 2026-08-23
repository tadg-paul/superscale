// ABOUTME: Keeps loaded pipelines between runs and lends one out for the duration of a run.
// ABOUTME: Actor confinement is what makes reuse safe; the instance never escapes.

import Foundation
import SuperscaleKit

/// Everything `Pipeline.init` reads, resolved.
///
/// `tileSize` is not the caller's optional: `Pipeline.init` substitutes the model's default for
/// nil, so nil and an explicit value equal to that default build the same pipeline. Keyed on the
/// argument rather than the result they would be two entries for one thing, and the next distinct
/// settings would release a live entry to make room for a duplicate.
public struct PipelineSettings: Hashable, Sendable {
    public let modelName: String
    public let tileSize: Int
    public let overlap: Int
    public let faceEnhance: Bool

    public init(
        modelName: String,
        tileSize: Int? = nil,
        overlap: Int = 16,
        faceEnhance: Bool
    ) throws {
        guard let info = ModelRegistry.model(named: modelName) else {
            throw SuperscaleError.modelNotFound(modelName)
        }
        self.modelName = modelName
        self.tileSize = tileSize ?? info.tileSize
        self.overlap = overlap
        self.faceEnhance = faceEnhance
    }
}

/// Holds loaded pipelines so a run does not pay for a model that is already in memory.
///
/// Loading takes roughly three seconds, and upscaling is reactive — a run happens whenever the
/// scale changes, the model changes, face enhancement is toggled, or a custom dimension settles.
/// Before this, nudging a slider reloaded the model that was loaded a second earlier.
///
/// Nothing was kept because keeping it would have been unsafe: `Pipeline` has a mutable
/// `onProgress` and holds Vision request state, so two runs sharing one instance would race on
/// both. Reuse and confinement are the same change.
public actor PipelineCache {
    public static let shared = PipelineCache()

    /// At most two are held. Each model is roughly 64 MB once loaded, so an unbounded cache
    /// trades a three-second load for tens of megabytes per model the user tries.
    ///
    /// The second slot exists for the face-enhancement toggle rather than for comparing models:
    /// `faceEnhance` is part of the key, and toggling it is one of the triggers that starts a
    /// run, so it alternates between two keys holding the same underlying model. One slot would
    /// reload on every press.
    static let capacity = 2

    private let load: @Sendable (PipelineSettings) throws -> Pipeline
    private var held: [PipelineSettings: Pipeline] = [:]
    /// Least recently used first.
    private var recency: [PipelineSettings] = []

    public init(
        load: @escaping @Sendable (PipelineSettings) throws -> Pipeline = { try PipelineCache.loadPipeline($0) }
    ) {
        self.load = load
    }

    public static func loadPipeline(_ settings: PipelineSettings) throws -> Pipeline {
        try Pipeline(
            modelName: settings.modelName,
            tileSize: settings.tileSize,
            overlap: settings.overlap,
            faceEnhance: settings.faceEnhance
        )
    }

    /// Lends a pipeline for the duration of `body`.
    ///
    /// `body` is synchronous, and that is load-bearing. Swift actors are reentrant: with an
    /// `async` body a second call could interleave at any suspension inside the first, and two
    /// runs would share one `Pipeline` — which is the thing this exists to prevent. A synchronous
    /// body has no suspension point, so non-overlap is a property of this signature.
    ///
    /// The same holds for `load`: were it async, two concurrent first uses of the same settings
    /// would both find nothing held and both load.
    public func withPipeline<T: Sendable>(
        _ settings: PipelineSettings,
        _ body: @Sendable (Pipeline) throws -> T
    ) throws -> T {
        // A run can wait: while one body executes — three seconds for a real upscale — every
        // other call queues behind it, and that queue is where superseded runs accumulate. One
        // already cancelled should not reach the point of being lent a pipeline. The tile loop
        // would stop it a moment later, but that check belongs to another component and was
        // added for another reason.
        try Task.checkCancellation()

        let pipeline = try pipeline(for: settings)
        defer {
            // The observer does not outlive its run. Left set, it holds whatever the caller
            // captured — in the application, a continuation feeding a view model — for as long as
            // the pipeline is held, which is now the life of the process.
            pipeline.onProgress = nil
        }
        return try body(pipeline)
    }

    private func pipeline(for settings: PipelineSettings) throws -> Pipeline {
        if let existing = held[settings] {
            touch(settings)
            return existing
        }

        // A load that fails holds nothing, so a transient failure does not poison the entry.
        let loaded = try load(settings)
        held[settings] = loaded
        touch(settings)
        releaseBeyondCapacity()
        return loaded
    }

    private func touch(_ settings: PipelineSettings) {
        recency.removeAll { $0 == settings }
        recency.append(settings)
    }

    private func releaseBeyondCapacity() {
        while recency.count > Self.capacity {
            let leastRecentlyUsed = recency.removeFirst()
            held.removeValue(forKey: leastRecentlyUsed)
        }
    }
}
