// ABOUTME: The chain of locked iterations, shown as a strip beneath the canvas.
// ABOUTME: Each entry is viewable, so an earlier iteration can be returned to and saved.

import SuperscaleUXCore
import SwiftUI

/// The lock chain: what the image was at each step the user chose to keep.
///
/// A strip beneath the canvas rather than a sidebar. Section 3.9 says sidebar, and a sidebar
/// costs width the canvas is required to keep — AC87.2 puts the image at 60% of the window at
/// the minimum size, and a third column would take it below that. A filmstrip spends height
/// instead, which the criterion does not claim, and reads as a history rather than as navigation.
struct LockChainStrip: View {
    let iterations: [Asset]
    /// The iteration currently on the canvas, when one is being viewed rather than the live image.
    ///
    /// The reference rather than its identifier: `AssetReference.id` is internal, which is what
    /// stops a caller outside the package inventing a reference for a file it happens to know
    /// about (AC89.4). Comparing references respects that and needs nothing widened.
    let viewing: AssetReference?
    let onSelect: (AssetReference) -> Void
    let onReturn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Locked iterations")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Offered only while an iteration is open, because with the live image already on
                // the canvas there is nothing to return from. Keeping the chain present was only
                // half of what #111 asked for: without this a user reaches every iteration and
                // never the picture they were working on.
                if viewing != nil {
                    Button("Back to current", action: onReturn)
                        .font(.caption)
                        .buttonStyle(.link)
                        .accessibilityIdentifier("returnToCurrentButton")
                }
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(iterations) { iteration in
                        entry(iteration)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .frame(height: 96)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lockChain")
    }

    private func entry(_ iteration: Asset) -> some View {
        Button {
            onSelect(iteration.reference)
        } label: {
            VStack(spacing: 3) {
                thumbnail(iteration)
                Text(label(for: iteration))
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 72)
            }
        }
        .buttonStyle(.plain)
        .help("View this iteration")
        .accessibilityIdentifier("lockedIteration-\(iteration.id.uuidString)")
        // Which entry is open is a state a user can see, so it is carried as a value rather than
        // left to a tint. Guide section 3.9. A button carries a value reliably where a container
        // or a plain `Text` does not, which #117 established by measurement.
        .accessibilityValue(iteration.reference == viewing ? "Showing" : "Not showing")
    }

    @ViewBuilder
    private func thumbnail(_ iteration: Asset) -> some View {
        if let image = NSImage(contentsOf: iteration.fileURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            // A locked iteration whose file has gone stays in the chain, because the chain is the
            // record of what was made.
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 56, height: 44)
                .overlay(Image(systemName: "questionmark").foregroundStyle(.secondary))
        }
    }

    /// What produced the iteration, which is what a user recognises it by.
    private func label(for iteration: Asset) -> String {
        guard let filterID = iteration.provenance?.filterID, !filterID.isEmpty else {
            return iteration.role == .source ? "Original" : "Iteration"
        }
        return filterID
            .replacingOccurrences(of: "image-", with: "")
            .split(separator: "-")
            .dropFirst()
            .joined(separator: " ")
            .capitalized
    }
}
