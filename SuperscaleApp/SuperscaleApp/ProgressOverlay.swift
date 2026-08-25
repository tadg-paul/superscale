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
    }
}

#Preview {
    ProgressOverlay(message: "Processing tile 2 of 4...")
        .frame(width: 400, height: 300)
}
