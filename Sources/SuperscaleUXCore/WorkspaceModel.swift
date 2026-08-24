// ABOUTME: Holds the single workspace's state: the working image, the filter selection, and what
// ABOUTME: applying sends, so the behaviour is testable without launching a window.

import FalGenerationKit
import Foundation

/// The image the workspace is working on, reduced to what a filter needs of it.
///
/// Carries the encoded reference rather than an `NSImage`, because this type crosses into the
/// package where AppKit is not available and should not be.
public struct WorkingImage: Equatable, Sendable {
    /// The image encoded as the provider takes it.
    public let referenceValue: String
    public let hasWorkingImage: Bool

    public init(referenceValue: String, hasWorkingImage: Bool) {
        self.referenceValue = referenceValue
        self.hasWorkingImage = hasWorkingImage
    }
}

/// How an image arrived at the workspace.
///
/// The distinction exists only because the two paths used to resolve the upscale model
/// differently, which was D8. They now pass through one function, and the parameter is retained so
/// a future divergence has to be written deliberately rather than by omission.
public enum ImageArrival: Equatable, Sendable {
    case dropped
    case filterResult
}

public enum WorkspaceError: LocalizedError, Sendable {
    case sessionImageMissing(String)

    public var errorDescription: String? {
        switch self {
        case let .sessionImageMissing(path):
            return "That session's image is no longer on disk: \(path)"
        }
    }
}

public struct WorkspaceModel: Sendable {
    /// The documented flat rate for the MVP's one model.
    ///
    /// A constant rather than a request. Section 2.3 of the implementation guide fixes grok at 2c
    /// per image and takes the pricing client out of scope, so asking the provider what it charges
    /// would contradict what the application tells the user it is doing.
    public static let filterCostUSD = 0.02

    /// The most recent sessions the File menu offers.
    public static let recentSessionLimit = 10

    public let filters: [PromptPack]
    public let catalogueFailure: String?
    public var selection: FilterSelection
    public var workingImage: WorkingImage?
    /// The upscaled rendering of the working image, when a scale is selected.
    ///
    /// Held separately and never sent. A filter reads the working image at its own resolution.
    public var upscaledRendering: WorkingImage?
    public let isGenerationConfigured: Bool

    public init(
        filters: [PromptPack],
        workingImage: WorkingImage?,
        upscaledRendering: WorkingImage? = nil,
        isGenerationConfigured: Bool = true,
        catalogueFailure: String? = nil
    ) {
        self.filters = filters
        self.workingImage = workingImage
        self.upscaledRendering = upscaledRendering
        self.isGenerationConfigured = isGenerationConfigured
        self.catalogueFailure = catalogueFailure
        self.selection = FilterSelection(filters: filters)
    }

    /// Whether there is anything to apply, and anything to apply it to.
    public var canApply: Bool {
        selection.canApply && workingImage?.hasWorkingImage == true && isGenerationConfigured
    }

    /// Whether the local half of the application is available, which does not depend on a key.
    public var canUpscale: Bool {
        workingImage?.hasWorkingImage == true
    }

    /// Whether the panel should offer a way to configure the missing key.
    public var offersRouteToSettings: Bool {
        !isGenerationConfigured
    }

    /// The request applying sends, or `nil` when there is nothing to send.
    ///
    /// The reference is the working image at its own resolution. The canvas shows the upscaled
    /// rendering by default, so sending what is on screen would be the obvious implementation and
    /// would breach AC79.2 and invariant I1: a cloud filter never receives pixels produced by an
    /// upscale targeting the user's chosen output size.
    public func applyRequest(modelID: String = FalGenerationRequest.defaultModelID) -> FalGenerationRequest? {
        guard canApply, let workingImage else { return nil }
        return selection.request(
            modelID: modelID,
            referenceImageURLs: [workingImage.referenceValue]
        )
    }

    /// Resolves the upscale model for an image, whichever way it arrived.
    ///
    /// D8 was the two arrival paths disagreeing: the configured default was honoured on the
    /// handoff and ignored on a drop, so the same file upscaled differently depending on how it
    /// got there. One function both paths call is the fix; the arrival is a parameter so that a
    /// deliberate divergence would have to be written rather than left out.
    public static func resolvedUpscaleModelID(
        preferred: String,
        arrival: ImageArrival,
        chosenInToolbar: String? = nil,
        isKnown: (String) -> Bool
    ) -> String {
        if let chosenInToolbar, chosenInToolbar == "auto" || isKnown(chosenInToolbar) {
            return chosenInToolbar
        }
        guard preferred == "auto" || isKnown(preferred) else { return "auto" }
        return preferred
    }

    /// The sessions the File menu offers, most recent first and bounded.
    public static func recentSessions(from sessions: [GenerationSessionRecord]) -> [GenerationSessionRecord] {
        Array(sessions.sorted { $0.timestamp > $1.timestamp }.prefix(recentSessionLimit))
    }

    /// Resolves a session's image, or reports that it is gone.
    ///
    /// Session assets live in Application Support, which users clear out, so a menu entry whose
    /// image has been deleted is ordinary rather than exotic.
    public static func workingImage(for session: GenerationSessionRecord) throws -> URL {
        guard let url = session.generatedAssetURL,
              FileManager.default.fileExists(atPath: url.path) else {
            throw WorkspaceError.sessionImageMissing(session.generatedAssetPath ?? "unknown path")
        }
        return url
    }
}
