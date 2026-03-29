// ABOUTME: About panel showing app info, version, installed models, and licences.
// ABOUTME: Opened from the toolbar ⓘ button.

import SuperscaleKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modelsSection
                    faceModelSection
                    linkSection
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Superscale")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(versionString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("By Taḋg Paul")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var versionString: String {
        // Read from the same source as CLI --version
        // The version is baked into SuperscaleCommand.swift at build time
        // For the GUI, read from the bundle info or fall back to a constant
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "v\(version)"
        }
        return "v1.0.1"
    }

    // MARK: - Models

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upscaling Models")
                .font(.headline)

            ForEach(ModelRegistry.models, id: \.name) { model in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: ModelRegistry.isInstalled(model)
                          ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(ModelRegistry.isInstalled(model)
                                         ? Color.green : Color.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(model.displayName)
                                .font(.callout)
                            Text(model.name)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text("BSD-3-Clause (Xintao Wang, 2021)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Face model

    private var faceModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Face Enhancement")
                .font(.headline)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: FaceModelRegistry.isInstalled
                      ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(FaceModelRegistry.isInstalled
                                     ? Color.green : Color.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("GFPGAN v1.4")
                            .font(.callout)
                        Text(FaceModelRegistry.isInstalled ? "installed" : "not installed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Non-commercial: NVIDIA Source Code Licence, CC BY-NC-SA 4.0")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Link

    private var linkSection: some View {
        Link(destination: URL(string: "https://github.com/tigger04/superscale")!) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text("github.com/tigger04/superscale")
            }
            .font(.caption)
        }
    }
}
