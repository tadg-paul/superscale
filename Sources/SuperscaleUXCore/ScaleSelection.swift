// ABOUTME: The scale control as a value: a genuine off state and a toggle-group transition.
// ABOUTME: Only the transition reaches a new selection, so no view can assign around it.

import Foundation

/// What the user can press on the scale control.
public enum ScaleChoice: Equatable, Sendable {
    case preset(Int)
    case custom
}

/// What is selected. `off` is a real state, not the absence of one: with nothing selected there
/// is no upscale, which is what lets a filter-first session skip work it would set aside.
public enum ScaleSelection: Equatable, Sendable {
    case off
    case preset(Int)
    case custom

    /// The selection after a choice is pressed.
    ///
    /// Pressing the active choice clears it, which is what makes the control a toggle group
    /// rather than a set of radio buttons.
    public func choosing(_ choice: ScaleChoice) -> ScaleSelection {
        guard !isActive(choice) else { return .off }
        switch choice {
        case let .preset(scale):
            return .preset(scale)
        case .custom:
            return .custom
        }
    }

    public func isActive(_ choice: ScaleChoice) -> Bool {
        switch (self, choice) {
        case let (.preset(selected), .preset(pressed)):
            return selected == pressed
        case (.custom, .custom):
            return true
        default:
            return false
        }
    }

    /// Whether any upscale is due at all.
    public var isOff: Bool {
        self == .off
    }
}

/// Everything a local upscale needs, and the only place the selection can change.
public struct UpscaleRunSettings: Equatable, Sendable {
    public private(set) var selection: ScaleSelection
    public private(set) var modelName: String
    public private(set) var faceEnhance: Bool
    /// Retained across a cleared selection: the typed dimensions are the user's work, and a
    /// toggle press is not a request to discard them.
    public private(set) var customWidth: Int?
    public private(set) var customHeight: Int?
    public private(set) var stretch: Bool

    public init(
        selection: ScaleSelection,
        modelName: String,
        faceEnhance: Bool,
        customWidth: Int?,
        customHeight: Int?,
        stretch: Bool
    ) {
        self.selection = selection
        self.modelName = modelName
        self.faceEnhance = faceEnhance
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.stretch = stretch
    }

    public mutating func choose(_ choice: ScaleChoice) {
        selection = selection.choosing(choice)
    }

    /// Replaces a selected scale with the model's native one. A cleared selection stays cleared:
    /// adopting a scale is not the same as creating a selection.
    public mutating func adoptNativeScale(_ scale: Int) {
        guard case .preset = selection else { return }
        selection = .preset(scale)
    }

    public mutating func setModel(named name: String, nativeScale: Int) {
        modelName = name
        adoptNativeScale(nativeScale)
    }

    public mutating func setFaceEnhance(_ enabled: Bool) {
        faceEnhance = enabled
    }

    /// Changing the dimensions never creates a selection. Choosing custom does that.
    public mutating func setCustomDimensions(width: Int?, height: Int?, stretch: Bool? = nil) {
        customWidth = width ?? customWidth
        customHeight = height ?? customHeight
        if let stretch { self.stretch = stretch }
    }

    /// How the selection is expressed to the upscale stage, or nothing when it is cleared.
    public var sizing: GUIUpscaleSizing? {
        switch selection {
        case .off:
            return nil
        case let .preset(scale):
            return .preset(scale: scale)
        case .custom:
            return .custom(width: customWidth, height: customHeight, stretch: stretch)
        }
    }

    public var stageOptions: UpscaleStageOptions? {
        sizing.map {
            UpscaleStageOptions(modelName: modelName, faceEnhance: faceEnhance, sizing: $0)
        }
    }
}
