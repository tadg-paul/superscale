// ABOUTME: Progress indicator overlay shown during image processing.
// ABOUTME: Displays a spinner and the current pipeline progress message.

import SwiftUI

struct ProgressOverlay: View {
    let message: String

    /// The widest the badge may become before its message wraps.
    ///
    /// A ceiling, not a width. `.frame(maxWidth:)` was applied *outside* the padding and *inside*
    /// the background, and a `maxWidth` frame takes the proposal clamped to the maximum rather than
    /// shrinking to its child — so on any canvas at least this wide the capsule was this wide,
    /// whatever the message said. The author measured the result as a box four times the width of
    /// its text, obscuring picture for no reason (#128).
    ///
    /// The bound is still wanted: without one, a long progress message runs the full width of a
    /// wide canvas. What changed is that it now bounds the *text*, which is a thing that has a
    /// natural width, rather than the badge, which does not.
    private static let widestMessage: CGFloat = 300

    /// Sized to its own content, never to the canvas.
    ///
    /// This filled the canvas and was given a `.thinMaterial` background, which is a blur, so every
    /// picture went soft the moment work began. Nobody asked for that. The picture is the thing the
    /// user came for and it is left exactly as it is; the indicator is a small badge over the top
    /// of it, with a background of its own so it stays legible against a bright photograph.
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            // The ceiling sits here, on the text. A `maxWidth` frame does not shrink to its child,
            // so bounding the *stack* set the badge's width; bounding the text lets the stack, the
            // padding and the capsule all size to what is actually being said.
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Self.widestMessage, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Translucent, at the author's figure. An opaque badge over the middle of a photograph hides
        // more of it than it needs to, and centring put it over the middle rather than the edge —
        // so AC119.1 asks more of this background than the top placement did.
        .background(.regularMaterial.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        // One element, whose frame is the badge's.
        //
        // Left as a plain container, the identifier the call site applies reaches the spinner and
        // the message alike, so `workingIndicator` matched several elements and a test reading
        // `.frame` got whichever came first in the tree — the spinner, which sits at the badge's
        // left edge rather than its centre. That is what #119 measured as an indicator 68 points
        // left of the picture: the badge was centred and the measurement was not of the badge.
        //
        // Combined rather than declared bare, so the message stays readable: `.combine` keeps the
        // children's text as this element's label, where `.ignore` would leave a badge that says
        // nothing to VoiceOver.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProgressOverlay(message: "Processing tile 2 of 4...")
        .frame(width: 400, height: 300)
}
