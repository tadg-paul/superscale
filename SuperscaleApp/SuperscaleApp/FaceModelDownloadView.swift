// ABOUTME: Face model download flow with licence acceptance.
// ABOUTME: Shown when user enables face enhancement without the model installed.

import SuperscaleKit
import SwiftUI

struct FaceModelDownloadView: View {
    @Binding var isPresented: Bool
    let onComplete: () -> Void

    @State private var stage: Stage = .confirm
    @State private var downloadProgress: String = ""
    @State private var errorMessage: String?

    enum Stage {
        case confirm, licence, downloading, complete, error
    }

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .confirm:
                confirmView
            case .licence:
                licenceView
            case .downloading:
                downloadingView
            case .complete:
                completeView
            case .error:
                errorView
            }
        }
        .frame(width: 480)
        .frame(minHeight: 300)
    }

    // MARK: - Confirm

    private var confirmView: some View {
        VStack(spacing: 16) {
            Image(systemName: "face.smiling")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("Download Face Enhancement Model?")
                .font(.headline)

            Text("GFPGAN v1.4 enhances faces in upscaled images. The model is ~325 MB and contains components with non-commercial licences.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Review Licence") { stage = .licence }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .padding(.top, 24)
    }

    // MARK: - Licence

    private var licenceView: some View {
        VStack(spacing: 0) {
            Text("Licence Terms")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                Text(licenceText)
                    .font(.system(.caption, design: .monospaced))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Accept & Download") {
                    stage = .downloading
                    startDownload()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    // MARK: - Downloading

    private var downloadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(downloadProgress.isEmpty ? "Downloading..." : downloadProgress)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Face enhancement model installed")
                .font(.headline)
            Spacer()
            Button("Done") {
                onComplete()
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .padding(16)
        }
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Download Failed")
                .font(.headline)
            if let msg = errorMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            Button("Close") { isPresented = false }
                .padding(16)
        }
    }

    // MARK: - Download logic

    private func startDownload() {
        downloadProgress = "Downloading GFPGAN model (~325 MB)..."

        Task.detached {
            do {
                let destDir = ModelRegistry.userModelsDirectory
                try FileManager.default.createDirectory(
                    at: destDir, withIntermediateDirectories: true)

                let destPath = destDir.appendingPathComponent(
                    FaceModelRegistry.modelFilename)

                if FileManager.default.fileExists(atPath: destPath.path) {
                    await MainActor.run {
                        stage = .complete
                    }
                    return
                }

                let downloadURL = FaceModelRegistry.downloadURL
                let tempZip = destDir.appendingPathComponent(
                    "\(FaceModelRegistry.modelFilename).zip")

                // Download
                await MainActor.run {
                    downloadProgress = "Downloading from GitHub..."
                }

                let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)

                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    throw NSError(domain: "Download", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                }

                try FileManager.default.moveItem(at: tempURL, to: tempZip)

                // Extract
                await MainActor.run {
                    downloadProgress = "Extracting model..."
                }

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-o", "-q", tempZip.path, "-d", destDir.path]
                unzip.standardOutput = FileHandle.nullDevice
                unzip.standardError = FileHandle.nullDevice
                try unzip.run()
                unzip.waitUntilExit()

                try? FileManager.default.removeItem(at: tempZip)

                if unzip.terminationStatus != 0 {
                    throw NSError(domain: "Extract", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Could not extract model archive"])
                }

                if !FileManager.default.fileExists(atPath: destPath.path) {
                    throw NSError(domain: "Extract", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Extracted archive did not contain \(FaceModelRegistry.modelFilename)"])
                }

                await MainActor.run {
                    stage = .complete
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    stage = .error
                }
            }
        }
    }

    // MARK: - Licence text

    private let licenceText = """
        GFPGAN Face Enhancement Model — Licence Notice

        This downloads CoreML-converted weights derived from GFPGAN,
        for use on Apple Silicon. The weights contain components with
        non-commercial licences:

          - StyleGAN2 (NVIDIA Source Code Licence — non-commercial use only)
            https://github.com/NVlabs/stylegan2/blob/master/LICENSE.txt

          - DFDNet (CC BY-NC-SA 4.0 — non-commercial, share-alike)
            https://creativecommons.org/licenses/by-nc-sa/4.0/

        By downloading, you confirm that:
          - You will use this model for non-commercial purposes only
          - Any redistribution of these weights must carry the same
            licence terms

        Full licence details: docs/model-licensing.md
        """
}
