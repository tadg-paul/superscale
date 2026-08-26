// ABOUTME: Verifies that every storage location the application uses derives from one configured root.
// ABOUTME: The workspace resolved its own root separately, so UI tests wrote into real user storage.

import CoreGraphics
import FalGenerationKit
import Foundation
import XCTest
@testable import SuperscaleUXCore

/// Where the application keeps what it produces.
///
/// The application resolved its storage root in two independent places — the entry point for the
/// coordinator and the session store, a view's property initialiser for the workspace — and
/// nothing held them together. A launch configured for testing redirected two of the three and
/// left the workspace writing into `~/Library/Application Support`.
///
/// These tests pin `StorageRoots`. That the *application* routes through it rather than around it
/// is RT-116.4, in the GUI suite, because the value that was wrong is produced in a SwiftUI
/// property initialiser no package test can reach.
final class StorageRootsTests: XCTestCase {

    /// A per-run directory beneath the operating system's temporary directory.
    ///
    /// Removed exactly, never a shared parent, on success and on failure alike.
    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-roots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// Whether `url` lies beneath `ancestor`, compared on standardized paths so that a symlinked
    /// temporary directory does not read as a different tree from its own children.
    private func isBeneath(_ url: URL, _ ancestor: URL) -> Bool {
        let child = url.standardizedFileURL.resolvingSymlinksInPath().path
        var parent = ancestor.standardizedFileURL.resolvingSymlinksInPath().path
        if !parent.hasSuffix("/") { parent += "/" }
        return child.hasPrefix(parent)
    }

    private func writeSource(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("source.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url
    }

    // MARK: - A configured root

    /// RT-116.1: with a root configured, an upscale location resolves beneath it.
    @MainActor
    func test_withARootConfiguredAnUpscaleResolvesBeneathIt_RT116_1() throws {
        let root = try scratchDirectory()
        let roots = StorageRoots.resolved(configuredRoot: root)
        let workspace = WorkspaceState(outputDirectory: roots.generated)

        let source = try writeSource(in: root)
        workspace.importImage(fileURL: source, pixelSize: CGSize(width: 2048, height: 1536))
        let upscale = try workspace.recordUpscale(pixelSize: CGSize(width: 4096, height: 3072))

        let asset = try workspace.graph.asset(for: upscale)
        XCTAssertTrue(
            isBeneath(asset.fileURL, root),
            "an upscale allocated \(asset.fileURL.path) outside the configured root \(root.path)"
        )
    }

    /// RT-116.2: with a root configured, a raise location resolves beneath it.
    @MainActor
    func test_withARootConfiguredARaiseResolvesBeneathIt_RT116_2() throws {
        let root = try scratchDirectory()
        let roots = StorageRoots.resolved(configuredRoot: root)
        let workspace = WorkspaceState(outputDirectory: roots.generated)

        let source = try writeSource(in: root)
        // Under the filterable minimum on its long edge, so a raise is what the workspace allocates.
        workspace.importImage(fileURL: source, pixelSize: CGSize(width: 240, height: 320))
        let allocation = try workspace.allocateRaiseToMinimum(
            pixelSize: CGSize(width: 960, height: 1280)
        )

        XCTAssertTrue(
            isBeneath(allocation.fileURL, root),
            "a raise allocated \(allocation.fileURL.path) outside the configured root \(root.path)"
        )
    }

    /// RT-116.5: with a root configured, the session history root resolves beneath it.
    func test_withARootConfiguredTheHistoryResolvesBeneathIt_RT116_5() throws {
        let root = try scratchDirectory()
        let roots = StorageRoots.resolved(configuredRoot: root)

        XCTAssertTrue(
            isBeneath(roots.history, root),
            "history resolved to \(roots.history.path) outside the configured root \(root.path)"
        )
    }

    /// RT-116.6: with a root configured, the generated-image store resolves beneath it.
    ///
    /// Asserted by storing an image rather than by reading the store's directory property, because
    /// where the store *says* it writes and where it writes are the two things this criterion is
    /// about keeping together.
    func test_withARootConfiguredTheGeneratedImageStoreResolvesBeneathIt_RT116_6() throws {
        let root = try scratchDirectory()
        let roots = StorageRoots.resolved(configuredRoot: root)
        let store = GeneratedImageStore(directory: roots.generated)

        let image = FalGeneratedImage(
            remoteURL: URL(string: "https://v3.fal.media/files/example.png")!,
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            warnings: []
        )
        let written = try store.store(image)

        XCTAssertTrue(
            isBeneath(written, root),
            "a generated image landed at \(written.path) outside the configured root \(root.path)"
        )
    }

    // MARK: - No configured root

    /// RT-116.3: with no root configured, all three storage kinds resolve beneath application support.
    ///
    /// The condition a careless redirection breaks. Reading the configured root unconditionally,
    /// with no fallback, moves every ordinary launch's storage somewhere new.
    func test_withNoRootConfiguredEveryKindResolvesBeneathApplicationSupport_RT116_3() throws {
        let roots = StorageRoots.resolved(configuredRoot: nil)

        let applicationSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let expectedRoot = applicationSupport.appendingPathComponent("Superscale", isDirectory: true)

        XCTAssertTrue(
            isBeneath(roots.generated, expectedRoot),
            "assets resolved to \(roots.generated.path), not beneath \(expectedRoot.path)"
        )
        XCTAssertTrue(
            isBeneath(roots.history, expectedRoot),
            "history resolved to \(roots.history.path), not beneath \(expectedRoot.path)"
        )
        // Generated images share the assets directory in production, so the third kind is asserted
        // at the same location deliberately rather than by omission.
        XCTAssertEqual(
            GeneratedImageStore(directory: roots.generated).directory,
            roots.generated,
            "the generated-image store took a directory other than the resolved one"
        )
    }
}
