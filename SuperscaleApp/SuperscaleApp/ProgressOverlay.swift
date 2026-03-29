// ABOUTME: Progress indicator overlay shown during image processing.
// ABOUTME: Displays a spinner and the current pipeline progress message.

import SwiftUI

struct ProgressOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ProgressOverlay(message: "Processing tile 2 of 4...")
        .frame(width: 400, height: 300)
}
