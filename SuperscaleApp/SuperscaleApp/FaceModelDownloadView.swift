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
        case confirm
        case licenceNvidia
        case licenceCCBYNCSA
        case downloading
        case complete
        case error
    }

    var body: some View {
        VStack(spacing: 0) {
            switch stage {
            case .confirm: confirmView
            case .licenceNvidia: nvidiaLicenceView
            case .licenceCCBYNCSA: ccLicenceView
            case .downloading: downloadingView
            case .complete: completeView
            case .error: errorView
            }
        }
        .frame(width: 540)
        .frame(minHeight: 400)
    }

    // MARK: - Confirm

    private var confirmView: some View {
        VStack(spacing: 16) {
            Image(systemName: "face.smiling")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)

            Text("Download Face Enhancement Model?")
                .font(.headline)

            Text("GFPGAN v1.4 enhances faces in upscaled images. The model is ~325 MB and contains components with two non-commercial licences that you must review and accept.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Review Licences") { stage = .licenceNvidia }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .padding(.top, 24)
    }

    // MARK: - NVIDIA Licence

    private var nvidiaLicenceView: some View {
        licenceScreen(
            title: "Licence 1 of 2: NVIDIA Source Code Licence",
            subtitle: "StyleGAN2 components — non-commercial use only",
            linkText: "View original at github.com/NVlabs/stylegan2",
            linkURL: "https://github.com/NVlabs/stylegan2/blob/master/LICENSE.txt",
            fullText: nvidiaLicenceText,
            onAgree: { stage = .licenceCCBYNCSA },
            onCancel: { isPresented = false }
        )
    }

    // MARK: - CC BY-NC-SA Licence

    private var ccLicenceView: some View {
        licenceScreen(
            title: "Licence 2 of 2: CC BY-NC-SA 4.0",
            subtitle: "DFDNet components — non-commercial, share-alike",
            linkText: "View original at creativecommons.org",
            linkURL: "https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode",
            fullText: ccLicenceText,
            onAgree: {
                stage = .downloading
                startDownload()
            },
            onCancel: { isPresented = false }
        )
    }

    // MARK: - Licence screen template

    private func licenceScreen(
        title: String, subtitle: String,
        linkText: String, linkURL: String,
        fullText: String,
        onAgree: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(linkText, destination: URL(string: linkURL)!)
                    .font(.caption)
            }
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                Text(fullText)
                    .font(.system(.caption2, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            Divider()

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("I Agree") { onAgree() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
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
                    await MainActor.run { stage = .complete }
                    return
                }

                let downloadURL = FaceModelRegistry.downloadURL
                let tempZip = destDir.appendingPathComponent(
                    "\(FaceModelRegistry.modelFilename).zip")

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

                await MainActor.run { stage = .complete }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    stage = .error
                }
            }
        }
    }

    // MARK: - Full licence texts (loaded from bundle resources)

    private var nvidiaLicenceText: String {
        loadLicence("LICENCE_NVIDIA")
    }

    private var ccLicenceText: String {
        loadLicence("LICENCE_CC_BY_NC_SA")
    }

    private func loadLicence(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Licence text not found. Run 'make fetch-licences' and rebuild."
        }
        return text
    }
}
