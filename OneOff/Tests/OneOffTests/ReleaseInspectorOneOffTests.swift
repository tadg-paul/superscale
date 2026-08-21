// ABOUTME: One-off verification that the GUI release inspector rejects sensitive artefacts.
// ABOUTME: Builds a synthetic app bundle in a temporary directory; no credentials are involved.

import Foundation
import XCTest

final class ReleaseInspectorOneOffTests: XCTestCase {

    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("superscale-release-inspector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot, FileManager.default.fileExists(atPath: fixtureRoot.path) {
            try FileManager.default.removeItem(at: fixtureRoot)
        }
        try super.tearDownWithError()
    }

    // OT-78.1
    func test_guiReleaseInspectorRejectsSessionAndSensitiveArtefacts_OT78_1() throws {
        let app = try makeAppFixture(promptPackCount: 86)
        let metadata = app.appendingPathComponent("Contents/Resources/metadata.json")
        try Data("{\"prompt\":\"private\"}".utf8).write(to: metadata)

        let result = try inspect(app)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("metadata.json"), result.output)
    }

    // MARK: - Helpers

    private func makeAppFixture(promptPackCount: Int) throws -> URL {
        let app = fixtureRoot.appendingPathComponent("Superscale.app")
        let resources = app
            .appendingPathComponent("Contents/Resources")
            .appendingPathComponent("Superscale_SuperscaleUXCore.bundle")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        for index in 0..<promptPackCount {
            let file = resources.appendingPathComponent(String(format: "image-fixture-%03d.md", index))
            try Data("Fixture prompt".utf8).write(to: file)
        }
        return app
    }

    private func inspect(_ app: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            projectRoot.appendingPathComponent("scripts/inspect-gui-release.sh").path,
            app.path,
        ]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The repository root, four levels above this file.
    ///
    /// This package lives at `<root>/OneOff`, so the path is
    /// `OneOffTests/ -> Tests/ -> OneOff/ -> <root>`. The depth differs from the
    /// main package's test targets, which sit two levels below the root.
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // OneOffTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // OneOff/
            .deletingLastPathComponent()  // repository root
    }
}
