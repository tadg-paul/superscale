// ABOUTME: Progress indicator overlay shown during image processing.
// ABOUTME: Displays a spinner and the current pipeline progress message.

import SwiftUI

struct ProgressOverlay: View {
    let message: String

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

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: Capsule())
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
