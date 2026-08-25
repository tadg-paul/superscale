// ABOUTME: The workspace's state, held as an asset graph rather than as properties on a view.
// ABOUTME: Owns the base, the candidate, the lock chain, and which of them the canvas shows.

import Combine
import CoreGraphics
import Foundation

/// What the application is working on.
///
/// The graph is the state rather than a library the view consults. A filter reads the base, lock
/// is the only thing that moves it, and an upscaled asset is refused as a stage input — all of
/// which the graph enforces by type. Held in a view instead, those rules were comments.
@MainActor
public final class WorkspaceState: ObservableObject {
    @Published public private(set) var graph: AssetGraph

    /// Whether the canvas shows the base rather than the candidate.
    ///
    /// A view choice and nothing else: toggling stores nothing and changes nothing, so it is free
    /// and reversible.
    @Published public var showsBase = false

    public init(outputDirectory: URL) {
        graph = AssetGraph(outputDirectory: outputDirectory)
    }

    /// The iterations behind the current base, oldest first.
    public var lockedIterations: [Asset] {
        graph.lockedIterations
    }

    /// Whether there is anything to compare the base against.
    public var canCompare: Bool {
        graph.candidate != nil
    }

    /// Where the base's pixels are, for a view that needs to draw them.
    ///
    /// Published so the view resolves it when the base *changes* rather than whenever SwiftUI
    /// evaluates a body. Reading it per evaluation decodes a photograph from disk on every progress
    /// tick, every hover phase and every keystroke in the dimension fields.
    public var baseFileURL: URL? {
        guard let reference = graph.base else { return nil }
        return try? graph.asset(for: reference).fileURL
    }

    /// Whether there are two different assets to compare.
    ///
    /// A question about lineage rather than about object identity: two `NSImage`s loaded from one
    /// file are different objects and the same picture, so comparing references is the only form of
    /// it that means anything.
    ///
    /// A picture against *its own upscale* is a real comparison and is wanted — that is the plain
    /// upscale case. What is not a comparison is a picture against itself.
    ///
    /// It suppresses the comparison only where it can *prove* both sides are one asset. With no
    /// base tracked there is nothing to prove it with, and the caller's own two images decide —
    /// returning false there suppressed the curtain outright, which is worse than the defect this
    /// guard exists to prevent.
    public func hasTwoAssetsToCompare(displaying displayed: AssetReference?) -> Bool {
        guard let base = graph.base, let displayed else { return true }
        return displayed != base
    }

    /// Whether a candidate exists to promote.
    public var canLock: Bool {
        graph.candidate != nil
    }

    /// The asset the canvas shows at model resolution.
    public var displayedAsset: AssetReference? {
        showsBase ? graph.base : (graph.candidate ?? graph.base)
    }

    /// The asset the canvas shows, preferring the upscaled rendering when one exists for it.
    ///
    /// The scale selection and this choice are independent: each of base, base upscaled, candidate
    /// and candidate upscaled is reachable.
    public func displayedAsset(upscaledWhenAvailable: Bool) -> AssetReference? {
        guard upscaledWhenAvailable else { return displayedAsset }
        // `try?` on a throwing function that returns an optional flattens to one optional, so the
        // guard already covers both "it threw" and "there is no current upscale".
        guard let rendering = try? graph.currentUpscale() else { return displayedAsset }
        return rendering
    }

    /// Adopts an imported image, starting a new chain.
    ///
    /// The chain belongs to the image it was built from: carrying it across would offer iterations
    /// of a picture no longer on screen.
    public func importImage(fileURL: URL, pixelSize: CGSize) {
        graph.importSource(fileURL: fileURL, pixelSize: pixelSize)
        showsBase = false
    }

    /// Records a filter result as the candidate, replacing any candidate before it.
    ///
    /// Shows the new candidate whichever was being displayed, because applying while showing the
    /// base would otherwise look as though nothing had happened.
    @discardableResult
    public func recordFilter(
        named filterID: String,
        fileURL: URL,
        pixelSize: CGSize,
        modelID: String = "",
        prompt: String = "",
        sessionID: UUID? = nil
    ) throws -> AssetReference {
        let input = try graph.input(for: .filter)
        let reference = try graph.recordFilterOutput(
            of: input,
            fileURL: fileURL,
            pixelSize: pixelSize,
            filter: FilterProvenance(
                filterID: filterID,
                modelID: modelID,
                prompt: prompt,
                sessionID: sessionID,
                secrets: []
            )
        )
        showsBase = false
        return reference
    }

    /// Allocates an upscale of whatever the canvas is showing.
    @discardableResult
    public func recordUpscale(pixelSize: CGSize, fileExtension: String = "png") throws -> AssetReference {
        let input = try graph.input(for: .upscale)
        let allocation = try graph.recordUpscale(
            of: input,
            pixelSize: pixelSize,
            fileExtension: fileExtension
        )
        return allocation.reference
    }

    /// Promotes the candidate to base.
    ///
    /// Promotes the candidate itself rather than what is on screen: with a scale selected the
    /// canvas shows the upscaled rendering, and locking that would store a derivation as the base.
    /// The graph refuses an upscaled asset here, so the rule is enforced rather than remembered.
    @discardableResult
    public func lock() throws -> AssetReference {
        let locked = try graph.lock()
        showsBase = false
        return locked
    }
}
