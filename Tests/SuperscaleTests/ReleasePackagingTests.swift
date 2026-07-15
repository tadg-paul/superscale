// ABOUTME: Verifies v2 GUI release packaging and documented provider scope.
// ABOUTME: Uses local synthetic app bundles so no paid services or credentials are involved.

import Foundation
import XCTest

final class ReleasePackagingTests: XCTestCase {
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = projectRoot
            .appendingPathComponent(".agent/tmp/release-packaging-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: fixtureRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let fixtureRoot, FileManager.default.fileExists(atPath: fixtureRoot.path) {
            try FileManager.default.removeItem(at: fixtureRoot)
        }
        try super.tearDownWithError()
    }

    // RT-78.1
    func test_guiReleaseInspectorAcceptsCompletePromptPackBundle_RT78_1() throws {
        let app = try makeAppFixture(promptPackCount: 86)

        let result = try inspect(app)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("86 prompt packs"), result.output)
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

    // OT-78.2
    func test_releaseEntryPointsKeepCLIAndGUIArtefactsSeparate_OT78_2() throws {
        let makefile = try readProjectFile("Makefile")
        let cliScript = try readProjectFile("scripts/release.sh")
        let guiScript = try readProjectFile("scripts/release-gui.sh")

        XCTAssertTrue(makefile.contains("release:\"".dropLast()))
        XCTAssertTrue(makefile.contains("@./scripts/release.sh $(RELEASE_VERSION)"))
        XCTAssertTrue(makefile.contains("release-gui:"))
        XCTAssertTrue(makefile.contains("@./scripts/release-gui.sh"))
        XCTAssertFalse(cliScript.contains("Superscale.app"))
        XCTAssertTrue(guiScript.contains("Superscale.app") || guiScript.contains("APP_NAME=\"Superscale\""))
        XCTAssertTrue(guiScript.contains("inspect-gui-release.sh"))
    }

    // RT-78.3
    func test_v2ReleaseChecklistStatesMVPProviderScope_RT78_3() throws {
        let checklist = try readProjectFile("docs/v2/RELEASE_CHECKLIST.md")

        XCTAssertTrue(checklist.contains("FAL is the only provider shipped in v2.0"))
        XCTAssertTrue(checklist.contains("Google and Replicate are future directions"))
        XCTAssertTrue(checklist.contains("not shipped in v2.0"))
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

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
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func readProjectFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: projectRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
