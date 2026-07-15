// ABOUTME: Verifies plain-file generation history storage, linkage, and redaction.
// ABOUTME: Ensures session metadata remains useful without persisting credentials.

import Foundation
import XCTest
@testable import SuperscaleUXCore

final class SessionStoreTests: XCTestCase {
    // RT-77.1, RT-77.7
    func test_generationSessionStoresAssetAndJSONMetadata() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GenerationSessionStore(rootDirectory: root)
        let source = root.appendingPathComponent("fixture.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: source)

        let record = try store.record(
            GenerationSessionDraft(
                prompt: "A lighthouse",
                modelID: "xai/grok-imagine-image",
                estimatedCost: 0.02,
                referencePaths: ["reference.png"],
                timestamp: Date(timeIntervalSince1970: 100),
                status: .generated,
                safeDiagnostic: nil
            ),
            generatedAsset: source
        )

        let generatedAssetPath = try XCTUnwrap(record.generatedAssetPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: generatedAssetPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.metadataPath))
        XCTAssertEqual(try store.sessions(), [record])
        XCTAssertEqual(record.prompt, "A lighthouse")
    }

    // RT-77.2
    func test_sessionMetadataRedactsSecretsAndAccountData() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GenerationSessionStore(rootDirectory: root)
        let record = try store.record(
            GenerationSessionDraft(
                prompt: "safe prompt",
                modelID: "model",
                estimatedCost: nil,
                referencePaths: [],
                timestamp: Date(timeIntervalSince1970: 100),
                status: .failed,
                safeDiagnostic: "Authorization: Key generation-secret; admin-secret denied"
            ),
            generatedAsset: nil,
            secrets: ["generation-secret", "admin-secret"]
        )

        let metadata = try String(contentsOfFile: record.metadataPath, encoding: .utf8)
        XCTAssertFalse(metadata.contains("generation-secret"))
        XCTAssertFalse(metadata.contains("admin-secret"))
        XCTAssertTrue(metadata.contains("[REDACTED]"))
        XCTAssertFalse(metadata.localizedCaseInsensitiveContains("current_balance"))
    }

    // RT-77.3, RT-77.4
    func test_upscaledAssetIsAssociatedAndCanReenterSharedUpscalePath() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GenerationSessionStore(rootDirectory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let generated = root.appendingPathComponent("generated.png")
        let upscaled = root.appendingPathComponent("upscaled.png")
        try Data("generated".utf8).write(to: generated)
        try Data("upscaled".utf8).write(to: upscaled)
        let record = try store.record(.fixture, generatedAsset: generated)

        let updated = try store.associateUpscaledAsset(upscaled, withSessionID: record.id)

        XCTAssertNotNil(updated.upscaledAssetPath)
        XCTAssertEqual(updated.upscaleSource, updated.generatedAssetURL.map(GUIUpscaleSource.generatedFile))
    }

    // RT-77.5
    func test_sessionsCanBeFilteredAcrossAllMVPStates() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GenerationSessionStore(rootDirectory: root)

        for status in GenerationSessionStatus.allCases {
            _ = try store.record(.fixture(status: status), generatedAsset: nil)
        }

        XCTAssertEqual(try store.sessions().count, GenerationSessionStatus.allCases.count)
        XCTAssertEqual(try store.sessions(matching: .failed).map(\.status), [.failed])
        XCTAssertEqual(try store.sessions(matching: .cancelled).map(\.status), [.cancelled])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private extension GenerationSessionDraft {
    static var fixture: GenerationSessionDraft { fixture(status: .generated) }

    static func fixture(status: GenerationSessionStatus) -> GenerationSessionDraft {
        GenerationSessionDraft(
            prompt: "fixture",
            modelID: "model",
            estimatedCost: nil,
            referencePaths: [],
            timestamp: Date(),
            status: status,
            safeDiagnostic: nil
        )
    }
}
