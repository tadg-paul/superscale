// ABOUTME: Holds the chosen filter and the editable text, so choosing is free and applying costs.
// ABOUTME: Builds the one request the application sends, or none when there is nothing to send.

import FalGenerationKit
import Foundation

/// Choosing a filter and applying it are two steps.
///
/// Choosing loads the filter's own wording into `text` and sends nothing, so a user can read all
/// eighty-six at no charge and see exactly what would be sent before paying for it. Applying sends
/// `text` as it stands. An edit lasts for that one run: it does not change the built-in filter and
/// does not survive choosing another.
///
/// A value type rather than an observable object, because there is no work here to own — this is
/// what the user has chosen and what they have typed, and nothing else.
public struct FilterSelection: Equatable, Sendable {
    public let filters: [PromptPack]
    public private(set) var selectedID: String?
    public var text: String

    public init(filters: [PromptPack] = [], selectedID: String? = nil, text: String = "") {
        self.filters = filters
        self.selectedID = selectedID
        self.text = text
    }

    public var selectedFilter: PromptPack? {
        selectedID.flatMap { id in filters.first { $0.id == id } }
    }

    /// Whether the box still holds the chosen filter's own wording.
    ///
    /// What the mark beside a filter's name is entitled to claim. It read from `selectedID` alone,
    /// so it stayed put through any amount of editing and went on naming a filter whose words were
    /// no longer in the box --- guide 2.3 allows the text to be adjusted per execution, and once it
    /// differs the mark asserts something untrue.
    ///
    /// Derived rather than cleared on the first keystroke, so retyping the original wording brings
    /// it back. A stored flag would need an edit to un-set it and an exact-match check to re-set it,
    /// which is this computation with a state variable in front of it.
    public var isShowingChosenFilterWording: Bool {
        guard let filter = selectedFilter else { return false }
        return filter.body == text
    }

    /// The text that would be sent, with surrounding whitespace removed.
    public var promptToApply: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether there is anything to send. An empty prompt is not free: it reaches a paid edit
    /// endpoint and returns something arbitrary, so a filter sitting chosen beside an empty box
    /// is still nothing to apply.
    public var canApply: Bool {
        !promptToApply.isEmpty
    }

    /// Chooses a filter, replacing whatever the field held — a previous filter's wording, an edit
    /// of it, or text the user wrote themselves. Choosing the filter already chosen yields its
    /// wording afresh, which is how a user reverts an edit they have decided against.
    public mutating func choose(_ id: String) {
        guard let filter = filters.first(where: { $0.id == id }) else { return }
        selectedID = filter.id
        text = filter.body
    }

    /// Detaches from the chosen filter, leaving the text alone: what is applied is what is in the
    /// box, and the user may still want it.
    public mutating func clearSelection() {
        selectedID = nil
    }

    /// The request the application sends, or `nil` when there is nothing to send.
    ///
    /// The refusal lives here rather than beside the button, because two implementations of one
    /// rule diverge and the user meets whichever the button happens to use.
    public func request(
        modelID: String,
        aspectRatio: String = "1:1",
        referenceImageURLs: [String] = []
    ) -> FalGenerationRequest? {
        guard canApply else { return nil }
        return FalGenerationRequest(
            prompt: promptToApply,
            modelID: modelID,
            aspectRatio: aspectRatio,
            referenceImageURLs: referenceImageURLs
        )
    }
}
