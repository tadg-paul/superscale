// ABOUTME: What the scale control shows: the scale in effect, and the one requested when they differ.
// ABOUTME: Derived from the picture and the selection, so the toolbar never has to correct itself.

import CoreGraphics
import Foundation

/// How a scale reads in the control.
public enum ScaleReadoutState: Equatable, Sendable {
    /// This is what will run.
    case inEffect
    /// The user asked for this and something smaller is running instead.
    case requestedNotInEffect
    /// Neither.
    case inactive
}

/// What the scale control reports.
///
/// The defect this exists to prevent: a picture too large for the requested scale was reduced to fit
/// memory, the status bar said so, and the 4x button stayed lit. A control reading 4x while 1x runs
/// is not a preserved choice — it is a false statement about the current state, and it is the more
/// prominent of the two things the user is looking at.
///
/// **Derived, not awaited.** `UpscaleDecision` is returned by `GUIUpscaleCoordinator.process`, which
/// invites reading the reduction from a completed run. That would show 4x, run, and then correct
/// itself to 2x: the same defect, briefer. `UpscaleCeiling.decide` is a pure function of the source
/// size and the request, so the truth is available the moment the picture's dimensions are known.
///
/// **It reports; it does not rewrite.** The stored `ScaleSelection` is untouched, which is what lets
/// a smaller picture later run at the scale originally asked for without the user reselecting it.
/// AC82.8 protects that choice from silent replacement, and this separates that protection from the
/// display question it was once wrongly used to settle.
public struct ScaleReadout: Equatable, Sendable {
    /// What the user chose.
    public let requested: ScaleSelection
    /// What will run, or nothing when no upscale fits.
    public let effective: ScaleSelection?
    /// Whether those differ.
    public let wasReduced: Bool
    /// What the custom dimension fields show, when custom sizing is in play.
    public let displayedDimensions: CGSize?
    /// What was typed into them.
    public let requestedDimensions: CGSize?

    /// The readout for a picture and a selection.
    ///
    /// With no picture there is nothing to judge against the ceiling, so the selection alone decides
    /// — which is what the control showed before any of this.
    public static func of(
        sourceSize: CGSize?,
        selection: ScaleSelection,
        customWidth: Int?,
        customHeight: Int?,
        stretch: Bool
    ) -> ScaleReadout {
        let typed = customWidth.map(CGFloat.init).flatMap { width in
            customHeight.map { CGSize(width: width, height: CGFloat($0)) }
        }

        guard let sourceSize, let sizing = requestedSizing(
            selection: selection, customWidth: customWidth, customHeight: customHeight,
            stretch: stretch)
        else {
            return ScaleReadout(
                requested: selection, effective: selection, wasReduced: false,
                displayedDimensions: typed, requestedDimensions: typed)
        }

        let decision = UpscaleCeiling.decide(sourceSize: sourceSize, requested: sizing)

        return ScaleReadout(
            requested: selection,
            effective: decision.sizing.map(selectionFor),
            wasReduced: decision.wasReduced,
            displayedDimensions: decision.sizing == nil ? typed : decision.outputSize,
            requestedDimensions: typed)
    }

    /// How a given choice reads.
    public func state(of choice: ScaleSelection) -> ScaleReadoutState {
        if let effective, choice == effective { return .inEffect }
        if choice == requested { return .requestedNotInEffect }
        return .inactive
    }

    /// Whether a choice can still be pressed.
    ///
    /// Always. Marking a scale as not in effect is a statement, not a restriction: the natural way
    /// to render it is to dim the control, and dimmed reads as disabled — which would trap the user
    /// at the reduced scale until they imported a different picture.
    public func isChoosable(_ choice: ScaleSelection) -> Bool { true }

    private static func requestedSizing(
        selection: ScaleSelection, customWidth: Int?, customHeight: Int?, stretch: Bool
    ) -> GUIUpscaleSizing? {
        switch selection {
        case .off:
            return nil
        case let .preset(scale):
            return .preset(scale: scale)
        case .custom:
            return .custom(width: customWidth, height: customHeight, stretch: stretch)
        }
    }

    private static func selectionFor(_ sizing: GUIUpscaleSizing) -> ScaleSelection {
        switch sizing {
        case let .preset(scale):
            return .preset(scale)
        case .custom:
            return .custom
        }
    }
}
