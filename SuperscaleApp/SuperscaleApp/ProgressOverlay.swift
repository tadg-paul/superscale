// ABOUTME: Progress indicator overlay shown during image processing.
// ABOUTME: Displays a spinner and the current pipeline progress message.

import SwiftUI

struct ProgressOverlay: View {
    let message: String

    // 🚫 `widestMessage`, a 300-point ceiling, is removed by #128. It was the defect rather than a
    // safeguard: a finite `.frame(maxWidth:)` takes the proposal clamped to the maximum instead of
    // shrinking to its child, so the badge came out at exactly the cap — measured at **301 points
    // of a 1080-point canvas** for a 30-character message. Moving the bound between the stack and
    // the text made no difference, because both positions pin. `.fixedSize` hugs; a cap does not.

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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // **`.fixedSize` is what makes this hug; `.frame(maxWidth:)` does not.**
        //
        // Measured, after two attempts that reasoned about it instead: with `.frame(maxWidth: 300)`
        // the badge came out at **301 points of a 1080-point canvas** for a 30-character message —
        // the cap, exactly, not the content. A finite `maxWidth` takes the proposal clamped to the
        // maximum; it does not shrink to its child. Moving that bound from the stack to the text
        // and back changed nothing the author could see, which is why the first fix was reported
        // still wrong.
        //
        // Fixed horizontally, the stack reports the width it actually wants and the capsule follows
        // it. The messages are short pipeline strings, so there is no cap: one would only ever
        // re-introduce the pinning this removes, and `lineLimit` handles anything unexpected.
        .fixedSize(horizontal: true, vertical: false)
        // Translucent, at the author's figure. An opaque badge over the middle of a photograph hides
        // more of it than it needs to, and centring put it over the middle rather than the edge —
        // so AC119.1 asks more of this background than the top placement did.
        //
        // Opacity on the **shape**, not on the view: `.opacity` applied to the whole view drops it
        // from the accessibility tree, which cost #122 a run, and a `Material` does not honour
        // `.opacity` as a shape style in the way a filled shape does.
        .background {
            Capsule()
                .fill(.regularMaterial)
                .opacity(0.7)
        }
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
