// ABOUTME: Verifies that the graph's allocated output locations are usable when it allocates them.
// ABOUTME: The directory was created by another component as a side effect, and six GUI tests failed.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

/// Whether an allocated location can actually be written to.
///
/// `AssetGraph` mints paths beneath `outputDirectory` and never created it. That worked only
/// because `GenerationCoordinator` created the same directory as a side effect on the ordinary
/// launch path, and the UI-test launch replaces that coordinator — so every raise allocated into a
/// directory that was not there, the write failed, and the user was shown *"The folder
/// 'raised-<uuid>.png' doesn't exist."*
///
/// These tests hold the contract. That the application meets it is RT-115.5, in the GUI suite,
/// because a package test constructs the graph with a directory it made itself and so cannot see
/// the defect at all — which is exactly why `make test` stayed green through six GUI failures.
final class AssetGraphOutputDirectoryTests: XCTestCase {

    /// A per-run directory beneath the operating system's temporary directory.
    ///
    /// Removed exactly, never a shared parent, on success and on failure alike.
    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("graph-output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func writeSource(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("source.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url
    }

    /// A graph whose output directory does not exist, beneath a scratch root that does.
    private func graphWithAbsentOutputDirectory() throws -> (AssetGraph, URL, URL) {
        let scratch = try scratchDirectory()
        let output = scratch.appendingPathComponent("Generated", isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.path),
            "the fixture must start with the output directory absent, or it proves nothing"
        )
        return (AssetGraph(outputDirectory: output), output, scratch)
    }

    // MARK: - The directory exists when the location is allocated

    /// RT-115.1: allocating a raise yields a location whose directory exists.
    func test_allocatingARaiseCreatesTheOutputDirectory_RT115_1() throws {
        var (graph, output, scratch) = try graphWithAbsentOutputDirectory()
        let source = graph.importSource(
            fileURL: try writeSource(in: scratch),
            pixelSize: CGSize(width: 240, height: 320)
        )

        let allocation = try graph.recordRaiseToMinimum(
            of: source, pixelSize: CGSize(width: 960, height: 1280)
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.path),
            "the output directory is still absent after allocating \(allocation.fileURL.lastPathComponent)"
        )
    }

    /// RT-115.2: allocating an upscale yields a location whose directory exists.
    func test_allocatingAnUpscaleCreatesTheOutputDirectory_RT115_2() throws {
        var (graph, output, scratch) = try graphWithAbsentOutputDirectory()
        let source = graph.importSource(
            fileURL: try writeSource(in: scratch),
            pixelSize: CGSize(width: 2048, height: 1536)
        )

        let allocation = try graph.recordUpscale(
            of: source, pixelSize: CGSize(width: 4096, height: 3072), fileExtension: "png"
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.path),
            "the output directory is still absent after allocating \(allocation.fileURL.lastPathComponent)"
        )
    }

    /// RT-115.3: a stage writing to a freshly allocated location succeeds.
    ///
    /// The assertion the other two imply and neither makes. A directory that exists is the means;
    /// bytes arriving at the allocated path is the end, and it is what failed in the application.
    func test_aStageWritesToAFreshlyAllocatedLocation_RT115_3() throws {
        var (graph, _, scratch) = try graphWithAbsentOutputDirectory()
        let source = graph.importSource(
            fileURL: try writeSource(in: scratch),
            pixelSize: CGSize(width: 240, height: 320)
        )

        let allocation = try graph.recordRaiseToMinimum(
            of: source, pixelSize: CGSize(width: 960, height: 1280)
        )
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: allocation.fileURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: allocation.fileURL.path))
    }

    /// RT-115.4: an output directory already holding assets is not disturbed by allocation.
    func test_anExistingOutputDirectoryIsNotDisturbed_RT115_4() throws {
        let scratch = try scratchDirectory()
        let output = scratch.appendingPathComponent("Generated", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let existing = output.appendingPathComponent("already-here.png")
        try Data([0x01, 0x02]).write(to: existing)

        var graph = AssetGraph(outputDirectory: output)
        let source = graph.importSource(
            fileURL: try writeSource(in: scratch),
            pixelSize: CGSize(width: 2048, height: 1536)
        )
        _ = try graph.recordUpscale(
            of: source, pixelSize: CGSize(width: 4096, height: 3072), fileExtension: "png"
        )

        XCTAssertEqual(
            try Data(contentsOf: existing), Data([0x01, 0x02]),
            "allocation rewrote or removed a file that was already in the output directory"
        )
    }

    /// RT-115.8: allocation succeeds where the directory already exists.
    ///
    /// Paired with RT-115.6: without this, an implementation that threw unconditionally would
    /// satisfy the failure case and break everything else.
    func test_allocationSucceedsWhereTheDirectoryExists_RT115_8() throws {
        let scratch = try scratchDirectory()
        let output = scratch.appendingPathComponent("Generated", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var graph = AssetGraph(outputDirectory: output)
        let source = graph.importSource(
            fileURL: try writeSource(in: scratch),
            pixelSize: CGSize(width: 2048, height: 1536)
        )

        XCTAssertNoThrow(
            try graph.recordUpscale(
                of: source, pixelSize: CGSize(width: 4096, height: 3072), fileExtension: "png"
            )
        )
    }

    // MARK: - Where the directory cannot be brought into existence

    /// RT-115.6: allocation throws rather than returning a location that will fail at write time.
    func test_allocationThrowsWhereTheDirectoryCannotBeCreated_RT115_6() throws {
        let scratch = try scratchDirectory()
        // A file where the directory would go. `createDirectory` cannot proceed through it.
        let output = scratch.appendingPathComponent("Generated", isDirectory: true)
        try Data([0x00]).write(to: output)

        var graph = AssetGraph(outputDirectory: output)
        let source = graph.importSource(
            fileURL: try writeSource(in: scratch),
            pixelSize: CGSize(width: 2048, height: 1536)
        )

        XCTAssertThrowsError(
            try graph.recordUpscale(
                of: source, pixelSize: CGSize(width: 4096, height: 3072), fileExtension: "png"
            ),
            "a location was returned for a directory that cannot exist"
        )
    }

    /// RT-115.7: the failure names the directory and carries the underlying reason.
    ///
    /// Two distinct impossibilities, because a message that names only the directory cannot tell a
    /// user which of them they are looking at. Read from the error a caller receives.
    func test_theFailureNamesTheDirectoryAndTheReason_RT115_7() throws {
        let scratch = try scratchDirectory()

        // Impossibility one: a file occupies the directory's own path.
        let occupied = scratch.appendingPathComponent("Occupied", isDirectory: true)
        try Data([0x00]).write(to: occupied)

        // Impossibility two: the directory would have to be created beneath a file.
        let blockingFile = scratch.appendingPathComponent("blocking-file")
        try Data([0x00]).write(to: blockingFile)
        let beneathAFile = blockingFile.appendingPathComponent("Generated", isDirectory: true)

        var reasons: [String] = []
        for output in [occupied, beneathAFile] {
            var graph = AssetGraph(outputDirectory: output)
            let source = graph.importSource(
                fileURL: try writeSource(in: scratch),
                pixelSize: CGSize(width: 2048, height: 1536)
            )
            do {
                _ = try graph.recordUpscale(
                    of: source, pixelSize: CGSize(width: 4096, height: 3072), fileExtension: "png"
                )
                XCTFail("allocation succeeded beneath \(output.path)")
            } catch {
                let description = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                XCTAssertTrue(
                    description.contains(output.lastPathComponent),
                    "the failure does not name the directory: \(description)"
                )
                // The path is removed before the two are compared. Left in, the descriptions differ
                // because the directories differ, and the assertion below would pass against an
                // implementation that names the directory and drops the reason entirely.
                reasons.append(
                    description
                        .replacingOccurrences(of: output.path, with: "<directory>")
                        .replacingOccurrences(of: output.lastPathComponent, with: "<directory>")
                )
            }
        }

        XCTAssertEqual(reasons.count, 2)
        XCTAssertNotEqual(
            reasons[0], reasons[1],
            "with the directory removed the two failures read alike, so the reason is not carried"
        )
    }
}
