// ABOUTME: Verifies the kit reports phases as values and stops the loops that do per-unit work.
// ABOUTME: Also holds the command-line tool's printed progress text in place.

import CoreGraphics
import XCTest
@testable import SuperscaleKit

final class PipelineProgressTests: XCTestCase {

    // MARK: - AC83.4 progress as values

    // RT-83.10
    func test_theTilePhaseCarriesCompletedAndTotalCounts_RT083_10() {
        let progress = PipelineProgress.tiling(completed: 5, total: 16)

        guard case let .tiling(completed, total) = progress else {
            return XCTFail("expected the tiling phase")
        }
        XCTAssertEqual(completed, 5)
        XCTAssertEqual(total, 16)
    }

    // RT-83.11
    func test_theFacePhaseCarriesTheNumberOfFaces_RT083_11() {
        let progress = PipelineProgress.enhancingFaces(count: 3)

        guard case let .enhancingFaces(count) = progress else {
            return XCTFail("expected the face-enhancement phase")
        }
        XCTAssertEqual(count, 3)
    }

    // RT-83.12
    //
    // The list belongs to the test rather than to the module: a list in production would be a
    // third enumeration of the cases and the only one the compiler does not check. `kind` and
    // `description` are both switches with no default, so a case added without being identified
    // and described does not compile.
    func test_everyPhaseIsDistinguishableWithoutReadingWording_RT083_12() {
        let reports: [PipelineProgress] = [
            .loading(fileName: "a.png"),
            .inspecting(width: 1, height: 1, scale: 1),
            .split(tiles: 1, tileSize: 1, overlap: 1),
            .tiling(completed: 1, total: 1),
            .stitching(width: 1, height: 1),
            .upscalingAlpha,
            .enhancingFaces(count: 1),
            .resizing(width: 1, height: 1),
            .writing(fileName: "a.png"),
            .finished(width: 1, height: 1, fileName: "a.png"),
            .warning("a"),
        ]

        let kinds = reports.map(\.kind)

        XCTAssertEqual(
            Set(kinds).count,
            reports.count,
            "two phases the kit reports share a kind"
        )
    }

    // MARK: - AC83.6 the command-line tool's text

    // RT-83.16
    func test_eachPhaseRendersToTheTextThePipelinePreviouslyReported_RT083_16() {
        XCTAssertEqual(
            "\(PipelineProgress.loading(fileName: "remy1.png"))",
            "Loading remy1.png..."
        )
        XCTAssertEqual(
            "\(PipelineProgress.stitching(width: 4096, height: 3072))",
            "Stitching output (4096×3072)..."
        )
        XCTAssertEqual("\(PipelineProgress.upscalingAlpha)", "Upscaling alpha channel...")
        XCTAssertEqual(
            "\(PipelineProgress.writing(fileName: "remy1_4x.png"))",
            "Writing remy1_4x.png..."
        )
    }

    // RT-83.17
    func test_aPhaseCarryingCountsRendersThemInTheSamePositions_RT083_17() {
        XCTAssertEqual(
            "\(PipelineProgress.tiling(completed: 3, total: 12))",
            "Processing tile 3 of 12..."
        )
        XCTAssertEqual(
            "\(PipelineProgress.enhancingFaces(count: 2))",
            "Enhancing 2 faces..."
        )
        XCTAssertEqual(
            "\(PipelineProgress.enhancingFaces(count: 1))",
            "Enhancing 1 face...",
            "the singular form the pipeline emits today"
        )
        XCTAssertEqual(
            "\(PipelineProgress.inspecting(width: 1024, height: 768, scale: 4))",
            "Input: 1024×768, scale: 4×"
        )
    }

    // MARK: - AC83.3 cancellation

    // RT-83.7
    func test_aCancelledTileRunLeavesTilesUnprocessed_RT083_7() async throws {
        let tiles = try makeTiles(count: 8)
        let processed = Counter()

        let task = Task {
            try Tiler.processTiles(tiles, scale: 1, tileSize: 64, report: { _ in }) { image in
                processed.increment()
                return image
            }
        }
        task.cancel()
        _ = try? await task.value

        XCTAssertLessThan(
            processed.value, tiles.count,
            "a cancelled run processed every tile"
        )
    }

    // RT-83.8
    func test_aCancelledTileRunReportsCancellationRatherThanAFailure_RT083_8() async throws {
        let tiles = try makeTiles(count: 8)

        let task = Task {
            try Tiler.processTiles(tiles, scale: 1, tileSize: 64, report: { _ in }) { $0 }
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("a cancelled run returned tiles")
        } catch is CancellationError {
            // The expected outcome.
        } catch {
            XCTFail("a cancelled run reported a failure rather than a cancellation: \(error)")
        }
    }

    // RT-83.9
    func test_aRunThatIsNotCancelledProcessesEveryTile_RT083_9() throws {
        let tiles = try makeTiles(count: 8)
        let processed = Counter()

        let result = try Tiler.processTiles(tiles, scale: 1, tileSize: 64, report: { _ in }) { image in
            processed.increment()
            return image
        }

        XCTAssertEqual(processed.value, tiles.count)
        XCTAssertEqual(result.count, tiles.count)
    }

    // RT-83.22
    func test_aCancelledFaceEnhancementPassLeavesFacesUnprocessed_RT083_22() async throws {
        let faces = (0..<6).map { CGRect(x: $0 * 10, y: 0, width: 8, height: 8) }
        let enhanced = Counter()

        let task = Task {
            try FaceEnhancer.forEachFace(faces) { _ in
                enhanced.increment()
            }
        }
        task.cancel()
        _ = try? await task.value

        XCTAssertLessThan(
            enhanced.value, faces.count,
            "a cancelled face pass enhanced every face"
        )
    }

    // MARK: - Helpers

    /// Counts closure invocations across the task boundary the tests cancel over.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    private func makeTiles(count: Int) throws -> [Tile] {
        let size = 64
        let bytesPerRow = size * 4
        var tiles: [Tile] = []
        for index in 0..<count {
            var pixels = [UInt8](repeating: 128, count: size * bytesPerRow)
            guard let context = CGContext(
                data: &pixels,
                width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let image = context.makeImage() else {
                throw ImageIOError.contextCreationFailed
            }
            tiles.append(
                Tile(
                    image: image,
                    origin: CGPoint(x: index * size, y: 0),
                    size: CGSize(width: size, height: size)
                )
            )
        }
        return tiles
    }
}
