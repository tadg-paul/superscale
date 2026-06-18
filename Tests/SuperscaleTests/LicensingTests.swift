// ABOUTME: Tests for licence files and third-party attribution.
// ABOUTME: Validates THIRD_PARTY_LICENSES content and GFPGAN exclusion from repo.

import CryptoKit
import XCTest

final class LicensingTests: XCTestCase {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }

    // RT-69.1: Superscale source licence, model licences, notice, and trademark docs are consistent
    func test_apache_source_license_preserves_model_license_split_RT69_1() throws {
        let license = try readProjectFile("LICENSE")
        XCTAssertTrue(license.contains("Apache License"),
                      "Source licence should be Apache-2.0")
        XCTAssertTrue(license.contains("Version 2.0"),
                      "Source licence should be Apache License 2.0")
        XCTAssertFalse(license.contains("MIT License"),
                       "Current source licence should no longer be MIT")

        let readme = try readProjectFile("README.md")
        XCTAssertTrue(readme.contains("Superscale source code is licensed under Apache-2.0"),
                      "README should identify Apache-2.0 for source code")
        XCTAssertTrue(readme.contains("Real-ESRGAN") && readme.contains("BSD-3-Clause"),
                      "README should preserve Real-ESRGAN BSD-3-Clause model licence")
        XCTAssertTrue(readme.contains("GFPGAN") && readme.contains("non-commercial"),
                      "README should preserve GFPGAN non-commercial model notice")
        XCTAssertFalse(readme.contains("MIT. Copyright Taḋg Paul"),
                       "README should not present MIT as the current source licence")
        XCTAssertTrue(readme.contains("docs/sslogo.svg") || readme.contains("docs/sslogo.png"),
                      "README should reference the Superscale logo asset")

        let thirdPartyLicenses = try readProjectFile("THIRD_PARTY_LICENSES")
        XCTAssertTrue(thirdPartyLicenses.contains("Real-ESRGAN Model Weights"),
                      "Third-party notices should keep Real-ESRGAN model attribution")
        XCTAssertTrue(thirdPartyLicenses.contains("BSD 3-Clause") ||
                      thirdPartyLicenses.contains("BSD-3-Clause"),
                      "Third-party notices should keep BSD-3-Clause text")
        XCTAssertTrue(thirdPartyLicenses.contains("Xintao Wang"),
                      "Third-party notices should keep Real-ESRGAN copyright holder")

        let notice = try readProjectFile("NOTICE")
        XCTAssertTrue(notice.contains("Superscale"),
                      "NOTICE should identify Superscale")
        XCTAssertTrue(notice.contains("Apache-2.0") || notice.contains("Apache License"),
                      "NOTICE should identify Apache source licensing")
        XCTAssertTrue(notice.contains("Real-ESRGAN") && notice.contains("BSD"),
                      "NOTICE should identify separately licensed Real-ESRGAN weights")
        XCTAssertTrue(notice.contains("trademark"),
                      "NOTICE should identify trademark ownership")

        let modelLicensing = try readProjectFile("docs/model-licensing.md")
        XCTAssertTrue(modelLicensing.contains("Apache-2.0"),
                      "Model licensing doc should mention Apache-2.0 source licensing")
        XCTAssertTrue(modelLicensing.contains("BSD-3-Clause"),
                      "Model licensing doc should preserve BSD-3-Clause model status")
        XCTAssertTrue(modelLicensing.contains("not persisted") ||
                      modelLicensing.contains("transactional") ||
                      modelLicensing.contains("installation itself"),
                      "Model licensing doc should document GFPGAN acceptance auditability")

        let trademark = try readProjectFile("docs/trademark.md")
        XCTAssertTrue(trademark.contains("Superscale"),
                      "Trademark doc should identify Superscale")
        XCTAssertTrue(trademark.contains("logo"),
                      "Trademark doc should cover the logo")
        XCTAssertTrue(trademark.contains("based on Superscale"),
                      "Trademark doc should permit descriptive fork references")
        XCTAssertTrue(trademark.contains("official Superscale"),
                      "Trademark doc should prohibit confusing official-app presentation")
    }

    // RT-69.3: Release metadata and generated formula use Apache-2.0
    func test_release_metadata_uses_apache_license_RT69_3() throws {
        let formula = try readProjectFile("Formula/superscale.rb")
        XCTAssertTrue(formula.contains(#"license "Apache-2.0""#),
                      "Checked-in Homebrew formula should use Apache-2.0")
        XCTAssertFalse(formula.contains(#"license "MIT""#),
                       "Checked-in Homebrew formula should not use MIT")

        let releaseScript = try readProjectFile("scripts/release.sh")
        XCTAssertTrue(releaseScript.contains(#"license "Apache-2.0""#),
                      "Release script should generate Apache-2.0 formula metadata")
        XCTAssertFalse(releaseScript.contains(#"license "MIT""#),
                       "Release script should not generate MIT formula metadata")
    }

    // RT-69.4: GUI source and face-model licence resources and review surfaces remain present
    func test_gui_face_model_licence_surfaces_remain_present_RT69_4() throws {
        let project = try readProjectFile("SuperscaleApp/SuperscaleApp.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("LICENCE_NVIDIA.txt in Resources"),
                      "NVIDIA licence text should remain bundled in the app")
        XCTAssertTrue(project.contains("LICENCE_CC_BY_NC_SA.txt in Resources"),
                      "CC BY-NC-SA licence text should remain bundled in the app")

        let downloadView = try readProjectFile(
            "SuperscaleApp/SuperscaleApp/FaceModelDownloadView.swift")
        XCTAssertTrue(downloadView.contains("Review Licences"),
                      "GUI should still require licence review before download")
        XCTAssertTrue(downloadView.contains("NVIDIA Source Code Licence"),
                      "GUI should still show NVIDIA licence wording")
        XCTAssertTrue(downloadView.contains("CC BY-NC-SA 4.0"),
                      "GUI should still show CC BY-NC-SA wording")
        XCTAssertTrue(downloadView.contains("I Agree"),
                      "GUI should still require explicit agreement")
        XCTAssertTrue(downloadView.contains("LICENCE_NVIDIA"),
                      "GUI should load the NVIDIA licence resource")
        XCTAssertTrue(downloadView.contains("LICENCE_CC_BY_NC_SA"),
                      "GUI should load the CC BY-NC-SA licence resource")

        let modelPicker = try readProjectFile("SuperscaleApp/SuperscaleApp/ModelPicker.swift")
        XCTAssertTrue(modelPicker.contains("Non-commercial licence"),
                      "Model picker help should preserve non-commercial licence wording")

        let aboutView = try readProjectFile("SuperscaleApp/SuperscaleApp/AboutView.swift")
        XCTAssertTrue(aboutView.contains("Source code: Apache-2.0"),
                      "About panel should identify the Superscale source-code licence")
        XCTAssertTrue(aboutView.contains("Non-commercial: NVIDIA Source Code Licence, CC BY-NC-SA 4.0"),
                      "About panel should preserve GFPGAN licence summary")
    }

    // RT-027: THIRD_PARTY_LICENSES contains BSD-3-Clause attribution for Real-ESRGAN
    func test_third_party_licenses_contains_realesrgan_attribution_RT027() throws {
        let url = projectRoot.appendingPathComponent("THIRD_PARTY_LICENSES")
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(contents.contains("BSD 3-Clause") || contents.contains("BSD-3-Clause"),
                      "Expected BSD-3-Clause licence text")
        XCTAssertTrue(contents.contains("Xintao Wang"),
                      "Expected Xintao Wang copyright holder")
        XCTAssertTrue(contents.contains("2021"),
                      "Expected 2021 copyright year")
        XCTAssertTrue(contents.contains("Real-ESRGAN"),
                      "Expected Real-ESRGAN source reference")
    }

    // RT-028: No GFPGAN files tracked; .gitignore covers model weight files
    func test_gfpgan_files_not_tracked_and_gitignored_RT028() throws {
        // Verify no GFPGAN files are tracked in git
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["ls-files"]
        process.currentDirectoryURL = projectRoot
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let trackedFiles = String(data: data, encoding: .utf8) ?? ""
        // Exclude scripts — only flag model/weight files containing "gfpgan"
        let gfpganFiles = trackedFiles
            .components(separatedBy: "\n")
            .filter { $0.lowercased().contains("gfpgan") }
            .filter { !$0.hasPrefix("scripts/") }
        XCTAssertTrue(gfpganFiles.isEmpty,
                      "GFPGAN model files must not be tracked: \(gfpganFiles)")

        // Verify .gitignore covers model weight formats
        let gitignoreURL = projectRoot.appendingPathComponent(".gitignore")
        let gitignore = try String(contentsOf: gitignoreURL, encoding: .utf8)
        XCTAssertTrue(gitignore.contains("*.pth"),
                      ".gitignore must exclude .pth files (covers GFPGAN weights)")
        XCTAssertTrue(gitignore.contains("*.mlpackage"),
                      ".gitignore must exclude .mlpackage files (covers GFPGAN conversions)")
    }

    // RT-117: NVIDIA licence file matches canonical SHA-256
    func test_nvidia_licence_hash_RT117() throws {
        let path = projectRoot
            .appendingPathComponent("SuperscaleApp/SuperscaleApp/Resources/LICENCE_NVIDIA.txt")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: path.path),
                      "Licence file not found — run make fetch-licences")
        let data = try Data(contentsOf: path)
        let hash = sha256(data)
        XCTAssertEqual(hash, "803ddcc4dd20de6387e2e5731f6a864ea01364dd305b17bda7157bcab0c39295",
                       "NVIDIA licence text has changed from canonical version — review required")
    }

    // RT-118: CC BY-NC-SA 4.0 licence file matches canonical SHA-256
    func test_cc_licence_hash_RT118() throws {
        let path = projectRoot
            .appendingPathComponent("SuperscaleApp/SuperscaleApp/Resources/LICENCE_CC_BY_NC_SA.txt")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: path.path),
                      "Licence file not found — run make fetch-licences")
        let data = try Data(contentsOf: path)
        let hash = sha256(data)
        XCTAssertEqual(hash, "e66c269d4819aaab34b49ef5220c4ddab6756f21bb5180761a4eb8561f2b7bbd",
                       "CC BY-NC-SA 4.0 licence text has changed from canonical version — review required")
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func readProjectFile(_ path: String) throws -> String {
        let url = projectRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
