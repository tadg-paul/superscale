// ABOUTME: Verifies pipelines are reused across runs, bounded, and never used by two runs at once.
// ABOUTME: Every test builds its own cache with a counting loader; none touches the shared one.

import CoreGraphics
import Foundation
import SuperscaleKit
import XCTest
@testable import SuperscaleUXCore

final class PipelineCacheTests: XCTestCase {

    // MARK: - AC84.1 a held pipeline is reused

    // RT-84.1
    func test_twoRunsWithIdenticalSettingsLoadOnce() async throws {
        let loader = CountingLoader()
        let cache = PipelineCache(load: loader.load)
        let settings = try PipelineSettings.fixture()

        _ = try await cache.withPipeline(settings) { $0.modelName }
        _ = try await cache.withPipeline(settings) { $0.modelName }

        XCTAssertEqual(loader.count, 1)
    }

    // RT-84.2
    func test_theSecondRunReceivesTheSameInstanceAsTheFirst() async throws {
        let loader = CountingLoader()
        let cache = PipelineCache(load: loader.load)
        let settings = try PipelineSettings.fixture()

        let first = try await cache.withPipeline(settings) { ObjectIdentifier($0) }
        let second = try await cache.withPipeline(settings) { ObjectIdentifier($0) }

        XCTAssertEqual(first, second)
    }

    // RT-84.3
    func test_returningToAHeldPipelineAfterAnotherLoadsNeitherAgain() async throws {
        let loader = CountingLoader()
        let cache = PipelineCache(load: loader.load)
        let first = try PipelineSettings.fixture(modelName: "realesrgan-x4plus")
        let second = try PipelineSettings.fixture(modelName: "realesrgan-x2plus")

        _ = try await cache.withPipeline(first) { $0.modelName }
        _ = try await cache.withPipeline(second) { $0.modelName }
        _ = try await cache.withPipeline(first) { $0.modelName }
        _ = try await cache.withPipeline(second) { $0.modelName }

        XCTAssertEqual(loader.count, 2, "a held pipeline was reloaded")
    }

    // MARK: - AC84.2 settings nothing is held for load

    // RT-84.4
    func test_aDifferentModelNameLoads() async throws {
        try await assertLoadsTwice(
            try PipelineSettings.fixture(modelName: "realesrgan-x4plus"),
            try PipelineSettings.fixture(modelName: "realesrgan-x2plus")
        )
    }

    // RT-84.5
    func test_aDifferentTileSizeLoads() async throws {
        try await assertLoadsTwice(
            try PipelineSettings.fixture(tileSize: 256),
            try PipelineSettings.fixture(tileSize: 512)
        )
    }

    // RT-84.6
    func test_aDifferentFaceEnhancementSettingLoads() async throws {
        try await assertLoadsTwice(
            try PipelineSettings.fixture(faceEnhance: false),
            try PipelineSettings.fixture(faceEnhance: true)
        )
    }

    // RT-84.19
    //
    // An unresolved tile size and an explicit one equal to the model's default build the same
    // pipeline, so they must be the same key rather than two entries for one thing — which would
    // occupy both slots with a duplicate and release a live entry to make room.
    func test_anUnresolvedTileSizeMatchesTheModelsDefault_RT084_19() throws {
        let modelDefault = try XCTUnwrap(ModelRegistry.model(named: "realesrgan-x4plus")).tileSize

        let unresolved = try PipelineSettings.fixture(tileSize: nil)
        let explicit = try PipelineSettings.fixture(tileSize: modelDefault)

        XCTAssertEqual(unresolved, explicit)
    }

    // MARK: - AC84.3 the bound

    // RT-84.7
    func test_aThirdDistinctSettingReleasesTheLeastRecentlyUsed() async throws {
        let loader = CountingLoader()
        let cache = PipelineCache(load: loader.load)
        let first = try PipelineSettings.fixture(tileSize: 128)
        let second = try PipelineSettings.fixture(tileSize: 256)
        let third = try PipelineSettings.fixture(tileSize: 512)

        _ = try await cache.withPipeline(first) { $0.modelName }
        _ = try await cache.withPipeline(second) { $0.modelName }
        _ = try await cache.withPipeline(third) { $0.modelName }
        let beforeReturning = loader.count

        _ = try await cache.withPipeline(first) { $0.modelName }

        XCTAssertEqual(loader.count, beforeReturning + 1, "the least recently used was still held")
    }

    // RT-84.8
    //
    // Measures the bound through its consequence rather than through a published count: a cache
    // holding nothing fails because the two most recent reload, and one holding everything fails
    // because the two oldest do not.
    func test_afterFourSettingsOnlyTheTwoMostRecentAreStillHeld() async throws {
        let loader = CountingLoader()
        let cache = PipelineCache(load: loader.load)
        let settings = try (1...4).map { try PipelineSettings.fixture(tileSize: $0 * 128) }

        for setting in settings {
            _ = try await cache.withPipeline(setting) { $0.modelName }
        }
        XCTAssertEqual(loader.count, 4)

        // The two most recent are held; the two oldest are not.
        _ = try await cache.withPipeline(settings[3]) { $0.modelName }
        _ = try await cache.withPipeline(settings[2]) { $0.modelName }
        XCTAssertEqual(loader.count, 4, "a pipeline that should still be held was reloaded")

        _ = try await cache.withPipeline(settings[1]) { $0.modelName }
        _ = try await cache.withPipeline(settings[0]) { $0.modelName }
        XCTAssertEqual(loader.count, 6, "a pipeline that should have been released was still held")
    }

    // RT-84.9
    func test_usingAHeldPipelineMakesItTheMostRecentlyUsed() async throws {
        let loader = CountingLoader()
        let cache = PipelineCache(load: loader.load)
        let first = try PipelineSettings.fixture(tileSize: 128)
        let second = try PipelineSettings.fixture(tileSize: 256)
        let third = try PipelineSettings.fixture(tileSize: 512)

        _ = try await cache.withPipeline(first) { $0.modelName }
        _ = try await cache.withPipeline(second) { $0.modelName }
        // Touching the first makes the second the least recently used.
        _ = try await cache.withPipeline(first) { $0.modelName }
        _ = try await cache.withPipeline(third) { $0.modelName }
        let beforeReturning = loader.count

        _ = try await cache.withPipeline(first) { $0.modelName }

        XCTAssertEqual(
            loader.count, beforeReturning,
            "the pipeline touched most recently was released instead of the other"
        )
    }

    // MARK: - AC84.4 runs do not overlap

    // RT-84.10
    func test_aSecondRunDoesNotBeginUntilTheFirstHasReturned() async throws {
        let cache = PipelineCache(load: CountingLoader().load)
        let settings = try PipelineSettings.fixture()
        let log = EventLog()

        async let first: Void = cache.withPipeline(settings) { _ in
            log.record("enter-1")
            log.record("exit-1")
        }
        async let second: Void = cache.withPipeline(settings) { _ in
            log.record("enter-2")
            log.record("exit-2")
        }
        _ = try await (first, second)

        let events = log.events
        XCTAssertEqual(events.count, 4)
        // Whichever ran first, its exit precedes the other's entry.
        let firstExit = try XCTUnwrap(events.firstIndex { $0.hasPrefix("exit") })
        let secondEntry = try XCTUnwrap(events.lastIndex { $0.hasPrefix("enter") })
        XCTAssertLessThan(firstExit, secondEntry, "the runs interleaved: \(events)")
    }

    // RT-84.11
    func test_progressReachesItsOwnRunsObserverAndNoOther() async throws {
        let cache = PipelineCache(load: CountingLoader().load)
        let settings = try PipelineSettings.fixture()
        let firstObserver = ProgressLog()
        let secondObserver = ProgressLog()

        try await cache.withPipeline(settings) { pipeline in
            pipeline.onProgress = { firstObserver.record($0) }
            pipeline.onProgress?(.upscalingAlpha)
        }
        try await cache.withPipeline(settings) { pipeline in
            pipeline.onProgress = { secondObserver.record($0) }
            pipeline.onProgress?(.stitching(width: 1, height: 1))
        }

        XCTAssertEqual(firstObserver.reports, [.upscalingAlpha])
        XCTAssertEqual(secondObserver.reports, [.stitching(width: 1, height: 1)])
    }

    // RT-84.17
    func test_aPipelineReturnedToTheCacheHoldsNoObserver() async throws {
        let cache = PipelineCache(load: CountingLoader().load)
        let settings = try PipelineSettings.fixture()

        try await cache.withPipeline(settings) { pipeline in
            pipeline.onProgress = { _ in }
        }
        let heldObserver = try await cache.withPipeline(settings) { $0.onProgress != nil }

        XCTAssertFalse(heldObserver, "the previous run's observer outlived it")
    }

    // RT-84.12
    func test_aFailureInOneRunLeavesALaterRunUnaffected() async throws {
        let cache = PipelineCache(load: CountingLoader().load)
        let settings = try PipelineSettings.fixture()

        do {
            try await cache.withPipeline(settings) { _ in throw StubRunFailure() }
            XCTFail("the failing run did not throw")
        } catch is StubRunFailure {
            // The expected outcome.
        }

        let name = try await cache.withPipeline(settings) { $0.modelName }
        XCTAssertEqual(name, "realesrgan-x4plus")
    }

    // RT-84.18
    func test_concurrentFirstUseOfTheSameSettingsLoadsOnce() async throws {
        let loader = CountingLoader()
        let cache = PipelineCache(load: loader.load)
        let settings = try PipelineSettings.fixture()

        async let first = cache.withPipeline(settings) { $0.modelName }
        async let second = cache.withPipeline(settings) { $0.modelName }
        _ = try await (first, second)

        XCTAssertEqual(loader.count, 1, "concurrent first use loaded twice")
    }

    // MARK: - AC84.5 a failed load is not held

    // RT-84.13
    func test_aLoadFailurePropagatesRatherThanYieldingAPipeline() async throws {
        let loader = CountingLoader(failFirst: 1)
        let cache = PipelineCache(load: loader.load)
        let settings = try PipelineSettings.fixture()

        do {
            _ = try await cache.withPipeline(settings) { $0.modelName }
            XCTFail("a failed load yielded a pipeline")
        } catch is StubLoadFailure {
            // The expected outcome.
        }
    }

    // RT-84.14
    func test_aLaterRunWithTheSameSettingsLoadsAgainAndSucceeds() async throws {
        let loader = CountingLoader(failFirst: 1)
        let cache = PipelineCache(load: loader.load)
        let settings = try PipelineSettings.fixture()

        _ = try? await cache.withPipeline(settings) { $0.modelName }
        let name = try await cache.withPipeline(settings) { $0.modelName }

        XCTAssertEqual(name, "realesrgan-x4plus")
        XCTAssertEqual(loader.count, 2, "the failure was sticky")
    }

    // MARK: - AC84.6 the application's path

    // RT-84.15
    //
    // Counts exactly one, and zero is the failure that matters: a processor that ignores the
    // cache and constructs a Pipeline directly calls this loader no times at all, which an
    // "at most once" assertion would accept.
    //
    // Needs the model, because Pipeline is a concrete class — a counting loader must still
    // return a real one, and a criterion about the application's path cannot be met below it.
    func test_twoUpscalesThroughTheProcessorCallTheLoaderExactlyOnce() async throws {
        try skipWithoutModel()
        let scratch = try makeScratch()
        let input = try makeSmallImage(in: scratch)
        let loader = CountingLoader()
        let processor = SuperscaleGUIUpscaleProcessor(cache: PipelineCache(load: loader.load))

        _ = try await processor.process(inputURL: input, options: .fixture, onProgress: { _ in })
        _ = try await processor.process(inputURL: input, options: .fixture, onProgress: { _ in })

        XCTAssertEqual(loader.count, 1, "the processor did not obtain its pipeline from the cache")
    }

    // RT-84.16
    func test_theProcessorsSecondUpscaleProducesTheSameResultAsItsFirst() async throws {
        try skipWithoutModel()
        let scratch = try makeScratch()
        let input = try makeSmallImage(in: scratch)
        let processor = SuperscaleGUIUpscaleProcessor(cache: PipelineCache(load: CountingLoader().load))

        let first = try await processor.process(inputURL: input, options: .fixture, onProgress: { _ in })
        let second = try await processor.process(inputURL: input, options: .fixture, onProgress: { _ in })

        XCTAssertEqual(first.imageData, second.imageData, "reuse changed the result")
        XCTAssertEqual(first.resolvedModelName, second.resolvedModelName)
    }

    // MARK: - Helpers

    private func skipWithoutModel() throws {
        let modelURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("models/RealESRGAN_x4plus.mlpackage")
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: modelURL.path),
            "x4plus model not found"
        )
    }

    /// A small input keeps each real upscale to roughly a second.
    private func makeSmallImage(in directory: URL) throws -> URL {
        let width = 32
        let height = 24
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 180
            pixels[index + 1] = 90
            pixels[index + 2] = 40
            pixels[index + 3] = 255
        }
        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw StubRunFailure()
        }
        let url = directory.appendingPathComponent("input.png")
        try ImageWriter.write(image, to: url, format: .png, colorSpace: nil)
        return url
    }

    /// A unique directory beneath the operating-system temporary directory, removed in teardown
    /// on success, on failure, and on handled interruption.
    private func makeScratch() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("superscale-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }
        return root
    }

    private func assertLoadsTwice(
        _ first: PipelineSettings,
        _ second: PipelineSettings,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let loader = CountingLoader()
        let cache = PipelineCache(load: loader.load)

        _ = try await cache.withPipeline(first) { $0.modelName }
        _ = try await cache.withPipeline(second) { $0.modelName }

        XCTAssertEqual(loader.count, 2, "the settings were treated as the same", file: file, line: line)
    }
}

/// Counts loads and can be made to fail the first few, so "loaded once" is observable without
/// loading a model.
final class CountingLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var loads = 0
    private let failFirst: Int

    init(failFirst: Int = 0) {
        self.failFirst = failFirst
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return loads
    }

    func load(_ settings: PipelineSettings) throws -> Pipeline {
        lock.lock()
        loads += 1
        let attempt = loads
        lock.unlock()

        if attempt <= failFirst { throw StubLoadFailure() }
        return try Pipeline(
            modelName: settings.modelName,
            tileSize: settings.tileSize,
            overlap: settings.overlap,
            faceEnhance: settings.faceEnhance
        )
    }
}

struct StubLoadFailure: Error {}
struct StubRunFailure: Error {}

/// Records the order of events across the task boundary the concurrency tests span.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(event)
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [PipelineProgress] = []

    var reports: [PipelineProgress] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ progress: PipelineProgress) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(progress)
    }
}

extension GUIUpscaleOptions {
    static var fixture: GUIUpscaleOptions {
        GUIUpscaleOptions(
            selectedModelName: "realesrgan-x4plus",
            faceEnhance: false,
            sizing: .preset(scale: 4)
        )
    }
}

extension PipelineSettings {
    static func fixture(
        modelName: String = "realesrgan-x4plus",
        tileSize: Int? = nil,
        overlap: Int = 16,
        faceEnhance: Bool = false
    ) throws -> PipelineSettings {
        try PipelineSettings(
            modelName: modelName,
            tileSize: tileSize,
            overlap: overlap,
            faceEnhance: faceEnhance
        )
    }
}
