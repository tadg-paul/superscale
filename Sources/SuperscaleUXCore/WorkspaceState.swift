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
        guard let displayed = displayedAsset else { return nil }
        guard upscaledWhenAvailable else { return displayed }
        // The upscale of *what is displayed*, not of the graph's working asset. The two differ
        // exactly when the filter toggle is showing the base, and asking the wrong question there
        // returns nothing — so the canvas would fall back to the base unupscaled while a scale was
        // selected, which AC89.6's enumeration calls the cheaper answer and the worse one: the user
        // could not tell whether they were looking at a rendering or a raw image.
        //
        // `try?` on a throwing function that returns an optional flattens to one optional, so the
        // guard already covers both "it threw" and "there is no current upscale".
        guard let rendering = try? graph.currentUpscale(of: displayed) else { return displayed }
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
        sessionID: UUID? = nil,
        sentSize: CGSize? = nil
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
                secrets: [],
                sentSize: sentSize
            )
        )
        showsBase = false
        return reference
    }

    /// Allocates an upscale of whatever the canvas is showing.
    ///
    /// **The canvas, not the graph's working asset.** `graph.input(for: .upscale)` returns the
    /// candidate when one exists, which is what the user is looking at *unless* the filter toggle is
    /// showing the base — and then the two disagree. AC89.6 requires the base's own upscale to be
    /// reachable, so an upscale started while showing the base must be of the base. The graph cannot
    /// know this; `showsBase` lives here.
    ///
    /// The application never took the wrong branch, because it hands `display(_:)` an explicit
    /// reference. This method was the one that disagreed with it.
    @discardableResult
    public func recordUpscale(pixelSize: CGSize, fileExtension: String = "png") throws -> AssetReference {
        guard let input = displayedAsset else { throw AssetGraphError.noWorkingAsset }
        try graph.validateStageInput(input)
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

    // MARK: - The filterable minimum

    /// What raising the base to the filterable minimum would come to, or nothing where it already
    /// suffices or there is nothing to raise.
    ///
    /// Guide 2.5: the floor is enforced continuously, not only on import. This is therefore asked
    /// whenever the base changes *and* whenever a setting change alters what would be sent, rather
    /// than once at import — the second is AC96.2, and an implementation checking only on import
    /// passes AC96.1 and leaves the reported defect in place on every subsequent change.
    public func raiseToMinimumNeeded() -> MinimumResolutionDecision? {
        guard let base = graph.base, let asset = try? graph.asset(for: base) else { return nil }
        let decision = MinimumResolution.decide(sourceSize: asset.pixelSize)
        return decision.wasRaised ? decision : nil
    }

    /// Allocates the raise, and returns where to write it.
    ///
    /// Allocation and adoption are separate for the same reason they are for an upscale: the work
    /// can fail, and a failed raise must not have already replaced the base.
    public func allocateRaiseToMinimum(
        pixelSize: CGSize, fileExtension: String = "png", promote: Bool = true
    ) throws -> UpscaleAllocation {
        let input = try graph.input(for: .filter)
        return try graph.recordRaiseToMinimum(
            of: input, pixelSize: pixelSize, fileExtension: fileExtension, promote: promote)
    }

    /// Makes an allocated raise the base, once its pixels exist.
    public func adoptRaise(_ reference: AssetReference) throws {
        try graph.promoteRaise(reference)
        showsBase = false
    }

}
