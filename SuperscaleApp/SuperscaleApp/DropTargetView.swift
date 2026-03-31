// ABOUTME: Drag-and-drop target area for image files with file chooser.
// ABOUTME: Displays a prominent drop zone with visual feedback and click-to-choose.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DropTargetView: View {
    let onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text("Drop an image here")
                .font(.title2)
                .foregroundStyle(isTargeted ? .primary : .secondary)
                .accessibilityIdentifier("dropTarget")

            Button("or click here to choose a file") {
                openFileChooser()
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(Color.accentColor)
            .accessibilityIdentifier("fileChooser")

            Text("PNG, JPEG, TIFF, HEIC")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .padding(24)
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleProviders(providers)
        }
    }

    private func openFileChooser() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image to upscale"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        onDrop([url])
    }

    private func handleProviders(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                let supportedExtensions = ["png", "jpg", "jpeg", "tiff", "tif", "heic"]
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    DispatchQueue.main.async {
                        onDrop([url])
                    }
                }
            }
        }
        return true
    }
}

#Preview {
    DropTargetView(onDrop: { _ in })
        .frame(width: 400, height: 300)
}
