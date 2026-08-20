// ABOUTME: Verifies non-commercial model weights stay out of the repository.
// ABOUTME: Verifies bundled licence texts match their canonical hashes.

import CryptoKit
import XCTest

final class LicensingTests: XCTestCase {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }

    // RT-028: No GFPGAN model weights are tracked in the repository
    func test_gfpgan_files_not_tracked_RT028() throws {
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
}
