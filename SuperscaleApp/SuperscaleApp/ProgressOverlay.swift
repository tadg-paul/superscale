// ABOUTME: Progress indicator overlay shown during image processing.
// ABOUTME: Displays the current pipeline message stacked a word to a line, with the spinner beneath.

import SwiftUI

struct ProgressOverlay: View {
    let message: String

    // 🚫 `widestMessage`, a 300-point ceiling, is removed by #128. It was the defect rather than a
    // safeguard: a finite `.frame(maxWidth:)` takes the proposal clamped to the maximum instead of
    // shrinking to its child, so the badge came out at exactly the cap — measured at **301 points
    // of a 1080-point canvas** for a 30-character message. `.fixedSize` hugs; a cap does not.

    /// The message as the author asked for it: **a word to a line, in capitals, spinner underneath.**
    ///
    /// Split explicitly rather than left to wrapping. Wrapping would need a width to break against,
    /// and a width is what #128 spent two attempts removing — it would put the badge back to being
    /// sized by a constant rather than by what is being said. Splitting on whitespace is
    /// predictable: the line count follows the words, and nothing here is sized by a number.
    ///
    /// Every message that reaches this view is short. `SizingLine`'s long sentence is not one of
    /// them — it is the status bar's, and the only caller is `MainView`'s `canvasWork.message`.
    private var lines: [String] {
        message
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).uppercased() }
    }

    /// Sized to its own content, never to the canvas.
    ///
    /// This filled the canvas and was given a `.thinMaterial` background, which is a blur, so every
    /// picture went soft the moment work began. Nobody asked for that. The picture is the thing the
    /// user came for and it is left exactly as it is; the indicator is a badge over the top of it,
    /// with a background of its own so it stays legible against a bright photograph.
    var body: some View {
        // **Vertical, and the spinner is last.** The author asked for this five times, most
        // recently as: APPLYING / FILTER / [spinner]. Four previous attempts changed the badge's
        // width, its opacity and its position while leaving it a single horizontal line with the
        // spinner in front — none of which was what was asked for. It is written here as the shape
        // he specified rather than as an interpretation of it.
        VStack(spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, word in
                Text(word)
                    // Larger, because "still too small" was the other half of the report every
                    // time. `.title3` against the previous `.callout` is a real step, and the
                    // tracking is widened because capitals set tight read as a block.
                    .font(.title3.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.primary)
                    // Identified so the *arrangement* is assertable, not merely the text. A test
                    // reading the combined label cannot tell a stack from a row — the words join
                    // the same way either way — and arrangement is the whole of what was asked for
                    // five times.
                    // 🚫 **No per-word identifier, after three runs trying to get one.** I wanted the
                    // words individually addressable so a test could assert the arrangement from
                    // their frames. They would not enter the accessibility tree: identified alone,
                    // declared as elements, and with the container's label removed — the query found
                    // nothing every time, and the container kept absorbing them.
                    //
                    // The badge stays `.combine`d, which is what #128 established and what the seven
                    // existing indicator tests were written against. The arrangement is asserted from
                    // **the badge's own height** instead, which is a real measurement of the thing
                    // that changed, and the capitals and word order from its combined label.
            }

            ProgressView()
                .controlSize(.small)
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        // **`.fixedSize` is what makes this hug; `.frame(maxWidth:)` does not.**
        //
        // Measured, after two attempts that reasoned about it instead: with `.frame(maxWidth: 300)`
        // the badge came out at **301 points of a 1080-point canvas** for a 30-character message —
        // the cap, exactly, not the content. Kept now that the stack is vertical, because the
        // widest line still decides the width and it must still be the content that decides it.
        .fixedSize(horizontal: true, vertical: false)
        // Translucent, at the author's figure. An opaque badge over the middle of a photograph hides
        // more of it than it needs to, and centring put it over the middle rather than the edge —
        // so AC119.1 asks more of this background than the top placement did.
        //
        // Opacity on the **shape**, not on the view: `.opacity` applied to the whole view drops it
        // from the accessibility tree, which cost #122 a run, and a `Material` does not honour
        // `.opacity` as a shape style in the way a filled shape does.
        //
        // A rounded rectangle rather than a capsule now that the badge is taller than it is wide in
        // places: a capsule's end caps eat the corners of a stacked word.
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .opacity(0.7)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        // One element, whose frame is the badge's.
        //
        // Left as a plain container, the identifier the call site applies reaches the spinner and
        // each word alike, so `workingIndicator` matched several elements and a test reading
        // `.frame` got whichever came first in the tree. That is what #119 measured as an indicator
        // 68 points left of the picture: the badge was centred and the measurement was not of the
        // badge. **More words now means more children, so this matters more than it did.**
        //
        // **`.contain` with an explicit label, rather than `.combine`.**
        //
        // `.combine` was chosen by #128 so the badge would say something to VoiceOver rather than
        // nothing, and that reason still holds — which is why the label is stated here explicitly
        // instead of being inherited. What `.combine` also did was **absorb the children**, and with
        // the badge now a stack, the children's frames are the only evidence of the arrangement the
        // author asked for. A test that can read only the joined label cannot tell a stack from a
        // row.
        //
        // Combined rather than declared bare, so the message stays readable: `.combine` keeps the
        // children's text as this element's label, where `.ignore` would leave a badge that says
        // nothing to VoiceOver. **Unchanged from #128**, after an attempt to switch to `.contain`
        // for the sake of a test was abandoned: see the note in the stack above.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProgressOverlay(message: "Applying filter")
        .frame(width: 400, height: 300)
}
