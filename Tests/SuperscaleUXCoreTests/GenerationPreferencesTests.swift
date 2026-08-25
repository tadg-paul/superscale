// ABOUTME: Verifies the output folder's default, its persistence, and its recovery when it vanishes.
// ABOUTME: Each test owns a preferences suite, so no run rewrites the author's real settings.

import Foundation
import XCTest
@testable import SuperscaleUXCore

/// The output folder.
///
/// There was no default at all: `GenerationPreferences.defaults` initialised `outputFolder` to nil,
/// so a user who had never opened Settings had nowhere for output to go.
///
/// Every test here builds its own `UserDefaults` suite and removes it afterwards.
/// `GenerationPreferencesStore` falls back to `.standard`, and a test taking that default would
/// rewrite the author's own output folder — the kind of state that is noticed weeks later.
final class GenerationPreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "superscale.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    private func store(folderExists: @escaping (URL) -> Bool = { _ in true })
        -> GenerationPreferencesStore
    {
        GenerationPreferencesStore(defaults: defaults, folderValidator: folderExists)
    }

    // RT-95.9
    func test_withNoStoredPreferenceTheOutputFolderIsDownloads_RT095_9() throws {
        let loaded = store().load()

        let downloads = try XCTUnwrap(
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        XCTAssertEqual(loaded.outputFolder, downloads)
    }

    // RT-95.10
    func test_aChosenFolderSurvivesARestart_RT095_10() throws {
        let chosen = FileManager.default.temporaryDirectory
            .appendingPathComponent("chosen-\(UUID().uuidString)", isDirectory: true)

        let preferences = GenerationPreferences(
            outputFolder: chosen,
            defaultModelID: GenerationPreferences.defaults.defaultModelID,
            defaultUpscaleModelID: GenerationPreferences.defaults.defaultUpscaleModelID,
            defaultPromptPackID: nil)
        try store().save(preferences)

        // A second store over the same defaults is what a restart looks like.
        XCTAssertEqual(store().load().outputFolder, chosen)
    }

    // RT-95.11
    //
    // An external disk, or a directory the user deleted. Without the fallback the application has
    // nowhere to write and nothing to say about it.
    func test_aStoredFolderThatNoLongerExistsFallsBackToDownloads_RT095_11() throws {
        let vanished = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString)", isDirectory: true)

        let preferences = GenerationPreferences(
            outputFolder: vanished,
            defaultModelID: GenerationPreferences.defaults.defaultModelID,
            defaultUpscaleModelID: GenerationPreferences.defaults.defaultUpscaleModelID,
            defaultPromptPackID: nil)
        try store().save(preferences)

        let loaded = store(folderExists: { $0 != vanished }).load()

        let downloads = try XCTUnwrap(
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        XCTAssertEqual(loaded.outputFolder, downloads)
        XCTAssertNotEqual(loaded.outputFolder, vanished)
    }

    // The default is resolved through `FileManager` rather than assembled from the home directory,
    // so it stays correct on a machine where Downloads has been relocated.
    func test_theDefaultIsResolvedRatherThanAssembled() throws {
        let resolved = try XCTUnwrap(GenerationPreferences.defaultOutputFolder)

        XCTAssertEqual(resolved.lastPathComponent, "Downloads")
        XCTAssertTrue(resolved.isFileURL)
    }
}
