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

    // MARK: - Full licence texts

    private let nvidiaLicenceText = """
    Copyright (c) 2019, NVIDIA Corporation. All rights reserved.

    This work is made available under the Nvidia Source Code License-NC.
    To view a copy of this license, visit
    https://nvlabs.github.io/stylegan2/license.html

    NVIDIA Source Code License for StyleGAN2

    1. Definitions

    "Licensor" means any person or entity that distributes its Work.

    "Software" means the original work of authorship made available under
    this License.

    "Work" means the Software and any additions to or derivative works of
    the Software that are made available under this License.

    The "Licensee" or "You" means an individual or Legal Entity exercising
    permissions granted by this License.

    2. Grant of Copyright License. Subject to the terms and conditions of
    this License, the Licensor hereby grants to You a worldwide,
    non-exclusive, no-charge, royalty-free copyright license to use, copy,
    modify, and distribute its Work and any derivative works thereof in
    source code or object code form, provided that You agree to the terms
    and conditions in this License.

    3. Restrictions.

    3.1 You may not use the Work for commercial purposes.

    3.2 You must give any other recipients of the Work or Derivative Works
    a copy of this License.

    3.3 If You modify the Work, You must cause any modified files to carry
    prominent notices stating that You changed the files.

    3.4 You may not use the trade names, trademarks, service marks, or
    product names of the Licensor, except as required for reasonable and
    customary use in describing the origin of the Work.

    4. Disclaimer of Warranty. THE WORK IS PROVIDED "AS IS" WITHOUT
    WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR IMPLIED,
    INCLUDING WARRANTIES OR CONDITIONS OF MERCHANTABILITY, FITNESS FOR A
    PARTICULAR PURPOSE, TITLE OR NON-INFRINGEMENT. YOU BEAR THE RISK OF
    UNDERTAKING ANY ACTIVITIES UNDER THIS LICENSE.

    5. Limitation of Liability. UNDER NO CIRCUMSTANCES SHALL THE LICENSOR
    BE LIABLE TO YOU ON ANY LEGAL THEORY FOR ANY SPECIAL, INCIDENTAL,
    CONSEQUENTIAL, PUNITIVE OR EXEMPLARY DAMAGES ARISING OUT OF THIS
    LICENSE OR THE USE OF THE WORK OR OTHERWISE, EVEN IF THE LICENSOR HAS
    BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

    6. Termination.

    6.1 This License will terminate automatically upon any breach by You
    of any term of this License.

    6.2 Notwithstanding the foregoing, if You breach any term of this
    License, and You cure such breach within 30 days of becoming aware of
    such breach, the License shall continue in full force and effect.

    6.3 This License shall terminate if You institute patent litigation
    against the Licensor (including a cross-claim or counterclaim in a
    lawsuit) alleging that the Work constitutes patent infringement.
    """

    private let ccLicenceText = """
    Creative Commons Attribution-NonCommercial-ShareAlike 4.0
    International Public License

    By exercising the Licensed Rights (defined below), You accept and
    agree to be bound by the terms and conditions of this Creative Commons
    Attribution-NonCommercial-ShareAlike 4.0 International Public License
    ("Public License"). To the extent this Public License may be
    interpreted as a contract, You are granted the Licensed Rights in
    consideration of Your acceptance of these terms and conditions, and
    the Licensor grants You such rights in consideration of benefits the
    Licensor receives from making the Licensed Material available under
    these terms and conditions.

    Section 1 — Definitions.

    a. Adapted Material means material subject to Copyright and Similar
       Rights that is derived from or based upon the Licensed Material and
       in which the Licensed Material is translated, altered, arranged,
       transformed, or otherwise modified in a manner requiring permission
       under the Copyright and Similar Rights held by the Licensor.

    b. Adapter's License means the license You apply to Your Copyright and
       Similar Rights in Your contributions to Adapted Material in
       accordance with the terms and conditions of this Public License.

    c. BY-NC-SA Compatible License means a license listed at
       creativecommons.org/compatiblelicenses, approved by Creative
       Commons as essentially the equivalent of this Public License.

    d. Copyright and Similar Rights means copyright and/or similar rights
       closely related to copyright.

    e. Licensed Material means the artistic or literary work, database, or
       other material to which the Licensor applied this Public License.

    f. Licensed Rights means the rights granted to You subject to the
       terms and conditions of this Public License, which are limited to
       all Copyright and Similar Rights that apply to Your use of the
       Licensed Material and that the Licensor has authority to license.

    g. Licensor means the individual(s) or entity(ies) granting rights
       under this Public License.

    h. NonCommercial means not primarily intended for or directed towards
       commercial advantage or monetary compensation.

    i. Share means to provide material to the public by any means or
       process that requires permission under the Licensed Rights, such as
       reproduction, public display, public performance, distribution,
       dissemination, communication, or importation.

    Section 2 — Scope.

    a. License grant.
       1. Subject to the terms and conditions of this Public License, the
          Licensor hereby grants You a worldwide, royalty-free,
          non-sublicensable, non-exclusive, irrevocable license to:
          A. reproduce and Share the Licensed Material, in whole or in
             part, for NonCommercial purposes only; and
          B. produce, reproduce, and Share Adapted Material for
             NonCommercial purposes only.

    b. Other rights.
       1. Moral rights are not licensed under this Public License.
       2. Patent and trademark rights are not licensed.
       3. The Licensor waives the right to collect royalties for the
          exercise of the Licensed Rights, whether directly or through a
          collecting society, for NonCommercial purposes only.

    Section 3 — License Conditions.

    a. Attribution. If You Share the Licensed Material, You must:
       1. retain identification of the creator(s) of the Licensed
          Material;
       2. a copyright notice;
       3. a notice that refers to this Public License;
       4. indicate if You modified the Licensed Material.

    b. ShareAlike. If You Share Adapted Material You produce, the
       Adapter's License You apply must be a Creative Commons license with
       the same License Elements (BY-NC-SA) or a BY-NC-SA Compatible
       License.

    Section 4 — Disclaimer of Warranties and Limitation of Liability.

    THE LICENSED MATERIAL IS PROVIDED "AS IS". THE LICENSOR MAKES NO
    WARRANTIES REGARDING THE LICENSED MATERIAL. THE LICENSOR SHALL NOT BE
    LIABLE FOR DAMAGES ARISING FROM USE OF THE LICENSED MATERIAL.

    Section 5 — Term and Termination.

    This Public License applies for the term of the Copyright and Similar
    Rights licensed here. If You fail to comply, Your rights terminate
    automatically. Rights may be reinstated if the violation is cured
    within 30 days.

    For the full legal text, see:
    https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
    """
}
