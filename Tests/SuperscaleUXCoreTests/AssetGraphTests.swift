// ABOUTME: Verifies the asset graph's lineage, lock chain, upscale lifecycle and stage boundary.
// ABOUTME: Covers the data-loss, corruption and stale-correlation defects closed by issue #81.

import CoreGraphics
import Foundation
import XCTest
@testable import SuperscaleUXCore

final class AssetGraphTests: XCTestCase {

    // MARK: - AC81.1 an upscaled asset is never a stage input

    // RT-81.1
    func test_filterInputIsTheBaseWhileAnUpscaledAssetExists() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let upscale = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png")

        let filterInput = try graph.input(for: .filter)

        XCTAssertEqual(filterInput, source)
        XCTAssertNotEqual(filterInput, upscale.reference)
    }

    // RT-81.2
    func test_upscaleInputIsTheWorkingAssetRatherThanAnExistingUpscale() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let filtered = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "filtered.png"),
            pixelSize: .fixture,
            filter: .fixture
        )
        let firstUpscale = try graph.recordUpscale(of: filtered, pixelSize: .large, fileExtension: "png")

        let upscaleInput = try graph.input(for: .upscale)

        XCTAssertEqual(upscaleInput, filtered)
        XCTAssertNotEqual(upscaleInput, firstUpscale.reference)
    }

    // RT-81.3
    func test_submittingAnUpscaledAssetAsAStageInputReportsTheRuleItBreaks() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let upscale = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png")
        let upscaledAssetID = try graph.asset(for: upscale.reference).id

        XCTAssertThrowsError(try GUIUpscaleSource(resolving: upscale.reference, in: graph)) { error in
            XCTAssertEqual(error as? AssetGraphError, .upscaledAssetIsNotAStageInput(upscaledAssetID))
        }
    }

    // RT-81.25
    func test_stageRequestedWithNoWorkingAssetReportsTheAbsence() throws {
        let graph = try makeGraph()

        XCTAssertThrowsError(try graph.input(for: .upscale)) { error in
            XCTAssertEqual(error as? AssetGraphError, .noWorkingAsset)
        }
        XCTAssertThrowsError(try graph.input(for: .filter)) { error in
            XCTAssertEqual(error as? AssetGraphError, .noWorkingAsset)
        }
    }

    // MARK: - AC81.2 a filter reads the base and replaces the candidate

    // RT-81.4
    func test_secondFilterWithoutAnInterveningLockReadsTheBase() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "first.png"),
            pixelSize: .fixture,
            filter: .fixture
        )

        let secondInput = try graph.input(for: .filter)

        XCTAssertEqual(secondInput, source)
        XCTAssertNotEqual(secondInput, first)
    }

    // RT-81.30
    func test_secondFilterWithoutAnInterveningLockReplacesTheCandidate() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "first.png"),
            pixelSize: .fixture,
            filter: .fixture(id: "warm")
        )

        let second = try graph.recordFilterOutput(
            of: try graph.input(for: .filter),
            fileURL: try placeholder(named: "second.png"),
            pixelSize: .fixture,
            filter: .fixture(id: "cool")
        )

        XCTAssertEqual(graph.candidate, second)
        XCTAssertNotEqual(graph.candidate, first)
    }

    // RT-81.5
    func test_secondFilterAfterALockReadsTheLockedResult() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "first.png"),
            pixelSize: .fixture,
            filter: .fixture
        )
        try graph.lock()

        let secondInput = try graph.input(for: .filter)

        XCTAssertEqual(secondInput, first)
    }

    // MARK: - AC81.3 the base changes only by an explicit lock

    // RT-81.6
    func test_applyingAFilterLeavesTheBaseUnchanged() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)

        _ = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "filtered.png"),
            pixelSize: .fixture,
            filter: .fixture
        )

        XCTAssertEqual(graph.base, source)
    }

    // RT-81.7
    func test_anUpscaleLeavesTheBaseUnchanged() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)

        _ = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png")

        XCTAssertEqual(graph.base, source)
    }

    // RT-81.8
    func test_lockWithNoCandidateLeavesTheBaseUnchangedAndReportsWhy() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)

        XCTAssertThrowsError(try graph.lock()) { error in
            XCTAssertEqual(error as? AssetGraphError, .noCandidateToLock)
        }
        XCTAssertEqual(graph.base, source)
    }

    // RT-81.9
    func test_lockCapturesTheCandidateRatherThanAnUpscaleOfIt() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let filtered = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "filtered.png"),
            pixelSize: .fixture,
            filter: .fixture
        )
        let upscale = try graph.recordUpscale(of: filtered, pixelSize: .large, fileExtension: "png")

        try graph.lock()

        XCTAssertEqual(graph.base, filtered)
        XCTAssertNotEqual(graph.base, upscale.reference)
        XCTAssertEqual(try graph.asset(for: XCTUnwrap(graph.base)).pixelSize, .fixture)
    }

    // MARK: - AC81.4 no upscale writes over another's output

    // RT-81.10
    func test_upscalesOfTwoDifferentWorkingAssetsOccupyDifferentPaths() throws {
        var graph = try makeGraph()
        let first = graph.importSource(fileURL: try placeholder(named: "first.png"), pixelSize: .fixture)
        let firstUpscale = try graph.recordUpscale(of: first, pixelSize: .large, fileExtension: "png")

        let second = graph.importSource(fileURL: try placeholder(named: "second.png"), pixelSize: .fixture)
        let secondUpscale = try graph.recordUpscale(of: second, pixelSize: .large, fileExtension: "png")

        XCTAssertNotEqual(firstUpscale.fileURL, secondUpscale.fileURL)
    }

    // RT-81.11
    func test_repeatedUpscalesOfTheSameWorkingAssetOccupyDifferentPaths() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)

        // Captured before the second upscale runs: the first is discarded once superseded,
        // and the property under test is that the second chose a path of its own.
        let firstPath = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png").fileURL
        let secondPath = try graph.recordUpscale(of: source, pixelSize: .larger, fileExtension: "png").fileURL

        XCTAssertNotEqual(firstPath, secondPath)
    }

    // RT-81.12
    func test_upscalingASessionsImageReadsTheGeneratedAssetAndSparesTheEarlierOutput() throws {
        let root = try makeScratch()
        let store = GenerationSessionStore(rootDirectory: root)
        let generated = root.appendingPathComponent("generated.png")
        try Data("generated".utf8).write(to: generated)
        let record = try store.record(.fixture, generatedAsset: generated)
        let upscaled = try store.associateUpscaledAsset(
            Data("first-upscale".utf8),
            fileExtension: "png",
            withSessionID: record.id
        )
        let firstUpscalePath = try XCTUnwrap(upscaled.upscaledAssetPath)

        let stageInput = try XCTUnwrap(upscaled.upscaleSource)
        let secondUpscale = try store.associateUpscaledAsset(
            Data("second-upscale".utf8),
            fileExtension: "png",
            withSessionID: record.id
        )

        XCTAssertEqual(stageInput.url, upscaled.generatedAssetURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstUpscalePath))
        XCTAssertNotEqual(secondUpscale.upscaledAssetPath, firstUpscalePath)
    }

    // MARK: - AC81.5 session attribution follows lineage

    // RT-81.13
    func test_anUpscaleDescendingFromASessionsAssetIsAssociatedWithThatSession() throws {
        var graph = try makeGraph()
        let sessionID = UUID()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let filtered = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "filtered.png"),
            pixelSize: .fixture,
            filter: .fixture(sessionID: sessionID)
        )
        let upscale = try graph.recordUpscale(of: filtered, pixelSize: .large, fileExtension: "png")

        XCTAssertEqual(try graph.sessionID(associatedWith: upscale.reference), sessionID)
    }

    // RT-81.14
    func test_anUpscaleOfAnImportedImageIsAssociatedWithNoSessionDespiteOneBeingPresent() throws {
        var graph = try makeGraph()
        let unrelatedSessionID = UUID()
        let firstSource = graph.importSource(fileURL: try placeholder(named: "first.png"), pixelSize: .fixture)
        _ = try graph.recordFilterOutput(
            of: firstSource,
            fileURL: try placeholder(named: "filtered.png"),
            pixelSize: .fixture,
            filter: .fixture(sessionID: unrelatedSessionID)
        )
        try graph.lock()

        let imported = graph.importSource(fileURL: try placeholder(named: "imported.png"), pixelSize: .fixture)
        let upscale = try graph.recordUpscale(of: imported, pixelSize: .large, fileExtension: "png")

        XCTAssertNil(try graph.sessionID(associatedWith: upscale.reference))
    }

    // RT-81.15
    func test_associationSurvivesAnInterveningUnrelatedUpscale() throws {
        var graph = try makeGraph()
        let sessionID = UUID()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let filtered = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "filtered.png"),
            pixelSize: .fixture,
            filter: .fixture(sessionID: sessionID)
        )
        let sessionUpscale = try graph.recordUpscale(of: filtered, pixelSize: .large, fileExtension: "png")

        let unrelated = graph.importSource(fileURL: try placeholder(named: "unrelated.png"), pixelSize: .fixture)
        let unrelatedUpscale = try graph.recordUpscale(of: unrelated, pixelSize: .large, fileExtension: "png")

        XCTAssertEqual(try graph.sessionID(associatedWith: sessionUpscale.reference), sessionID)
        XCTAssertNil(try graph.sessionID(associatedWith: unrelatedUpscale.reference))
    }

    // RT-81.19
    func test_anUpscaleWhoseAncestryCrossesTwoSessionsIsAssociatedWithTheNearer() throws {
        var graph = try makeGraph()
        let earlierSessionID = UUID()
        let nearerSessionID = UUID()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        _ = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "earlier.png"),
            pixelSize: .fixture,
            filter: .fixture(sessionID: earlierSessionID)
        )
        try graph.lock()
        let nearer = try graph.recordFilterOutput(
            of: try graph.input(for: .filter),
            fileURL: try placeholder(named: "nearer.png"),
            pixelSize: .fixture,
            filter: .fixture(sessionID: nearerSessionID)
        )
        let upscale = try graph.recordUpscale(of: nearer, pixelSize: .large, fileExtension: "png")

        XCTAssertEqual(try graph.sessionID(associatedWith: upscale.reference), nearerSessionID)
    }

    // MARK: - AC81.6 every locked iteration remains reachable

    // RT-81.16
    func test_afterThreeLocksTheChainYieldsThreePriorIterationsInOrder() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try applyFilterAndLock(&graph, name: "first")
        let second = try applyFilterAndLock(&graph, name: "second")
        _ = try applyFilterAndLock(&graph, name: "third")

        XCTAssertEqual(graph.lockedIterations.map(\.id), [source, first, second].map(\.id))
    }

    // RT-81.17
    func test_eachLockedIterationCarriesTheFilterIdentityThatProducedIt() throws {
        var graph = try makeGraph()
        _ = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        _ = try applyFilterAndLock(&graph, name: "warm")
        _ = try applyFilterAndLock(&graph, name: "cool")
        _ = try applyFilterAndLock(&graph, name: "grain")

        let iterations = graph.lockedIterations

        XCTAssertNil(iterations[0].provenance?.filterID, "an imported source is not produced by a filter")
        XCTAssertEqual(iterations[1].provenance?.filterID, "warm")
        XCTAssertEqual(iterations[2].provenance?.filterID, "cool")
    }

    // RT-81.18
    func test_provenanceHoldsNoCredentialMaterial() throws {
        var graph = try makeGraph()
        let secret = "fal-key-9f3c-live"
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let filtered = try graph.recordFilterOutput(
            of: source,
            fileURL: try placeholder(named: "filtered.png"),
            pixelSize: .fixture,
            filter: FilterProvenance(
                filterID: "warm",
                modelID: "xai/grok-imagine-image/edit",
                prompt: "warm the highlights, Authorization: Key \(secret)",
                sessionID: nil,
                secrets: [secret]
            )
        )

        let provenance = try XCTUnwrap(graph.asset(for: filtered).provenance)
        let encoded = try String(decoding: JSONEncoder().encode(provenance), as: UTF8.self)

        XCTAssertFalse(encoded.contains(secret))
        XCTAssertTrue(encoded.contains("[REDACTED]"))
    }

    // RT-81.20
    func test_aLockedIterationWhoseFileIsAbsentRemainsInTheChainAndReportsItselfUnavailable() throws {
        var graph = try makeGraph()
        _ = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try applyFilterAndLock(&graph, name: "warm")
        _ = try applyFilterAndLock(&graph, name: "cool")

        try FileManager.default.removeItem(at: try graph.asset(for: first).fileURL)

        XCTAssertEqual(graph.lockedIterations.count, 2)
        XCTAssertTrue(graph.lockedIterations.contains { $0.id == first.id })
        XCTAssertFalse(try graph.isAvailable(first))
    }

    // RT-81.32
    func test_aLockedIterationWhoseFileIsPresentReportsItselfAvailable() throws {
        var graph = try makeGraph()
        _ = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try applyFilterAndLock(&graph, name: "warm")
        _ = try applyFilterAndLock(&graph, name: "cool")

        XCTAssertTrue(try graph.isAvailable(first))
    }

    // MARK: - AC81.7 the current upscaled output

    // RT-81.21
    func test_anUpscaleOfTheWorkingAssetIsIdentifiableAsItsCurrentOutput() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let upscale = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png")

        XCTAssertEqual(try graph.currentUpscale(), upscale.reference)
    }

    // RT-81.22
    func test_aSecondUpscaleOfTheSameWorkingAssetBecomesCurrentInPlaceOfTheFirst() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png")

        let second = try graph.recordUpscale(of: source, pixelSize: .larger, fileExtension: "png")

        XCTAssertEqual(try graph.currentUpscale(), second.reference)
        XCTAssertThrowsError(try graph.asset(for: first.reference))
    }

    // RT-81.23
    func test_applyingAFilterLeavesNoCurrentUpscaledOutput() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        _ = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png")

        _ = try graph.recordFilterOutput(
            of: try graph.input(for: .filter),
            fileURL: try placeholder(named: "filtered.png"),
            pixelSize: .fixture,
            filter: .fixture
        )

        XCTAssertNil(try graph.currentUpscale())
    }

    // RT-81.24
    func test_anOutputSupersededByALaterOneIsDiscarded() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png")
        try Data("first".utf8).write(to: first.fileURL)

        let second = try graph.recordUpscale(of: source, pixelSize: .larger, fileExtension: "png")
        try Data("second".utf8).write(to: second.fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
    }

    // RT-81.26
    func test_theCurrentOutputIsRetainedRatherThanDiscardedAlongsideSupersededOnes() throws {
        var graph = try makeGraph()
        let source = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)
        let first = try graph.recordUpscale(of: source, pixelSize: .large, fileExtension: "png")
        try Data("first".utf8).write(to: first.fileURL)

        let second = try graph.recordUpscale(of: source, pixelSize: .larger, fileExtension: "png")
        try Data("second".utf8).write(to: second.fileURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: second.fileURL.path))
        XCTAssertEqual(try graph.currentUpscale(), second.reference)
    }

    // RT-81.31
    func test_discardingASupersededOutputLeavesTheSourceAndLockedIterationsPresent() throws {
        var graph = try makeGraph()
        let sourceURL = try placeholder(named: "source.png")
        _ = graph.importSource(fileURL: sourceURL, pixelSize: .fixture)
        let locked = try applyFilterAndLock(&graph, name: "warm")
        let lockedURL = try graph.asset(for: locked).fileURL
        let working = try graph.input(for: .upscale)

        let first = try graph.recordUpscale(of: working, pixelSize: .large, fileExtension: "png")
        try Data("first".utf8).write(to: first.fileURL)
        let second = try graph.recordUpscale(of: working, pixelSize: .larger, fileExtension: "png")
        try Data("second".utf8).write(to: second.fileURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockedURL.path))
    }

    // MARK: - AC81.8 the stage boundary

    // RT-81.27
    func test_aStageRejectsAnAssetReferenceTheGraphDoesNotHold() throws {
        var holder = try makeGraph()
        let foreign = holder.importSource(fileURL: try placeholder(named: "foreign.png"), pixelSize: .fixture)

        var graph = try makeGraph()
        _ = graph.importSource(fileURL: try placeholder(named: "source.png"), pixelSize: .fixture)

        XCTAssertThrowsError(try GUIUpscaleSource(resolving: foreign, in: graph)) { error in
            XCTAssertEqual(error as? AssetGraphError, .unknownAsset(foreign.id))
        }
    }

    // RT-81.28
    func test_theSessionToStagePathYieldsTheAssetTheSessionProduced() throws {
        let root = try makeScratch()
        let store = GenerationSessionStore(rootDirectory: root)
        let generated = root.appendingPathComponent("generated.png")
        try Data("generated".utf8).write(to: generated)
        let record = try store.record(.fixture, generatedAsset: generated)

        let upscaled = try store.associateUpscaledAsset(
            Data("upscale".utf8),
            fileExtension: "png",
            withSessionID: record.id
        )
        let stageInput = try XCTUnwrap(upscaled.upscaleSource)

        XCTAssertEqual(stageInput.url, upscaled.generatedAssetURL)
        XCTAssertNotEqual(stageInput.url, upscaled.upscaledAssetURL)
        XCTAssertEqual(stageInput.sessionID, record.id)
    }

    // RT-81.29
    func test_theDisplayPathStillResolvesTheFinishedImage() throws {
        let root = try makeScratch()
        let store = GenerationSessionStore(rootDirectory: root)
        let generated = root.appendingPathComponent("generated.png")
        try Data("generated".utf8).write(to: generated)
        let record = try store.record(.fixture, generatedAsset: generated)

        let upscaled = try store.associateUpscaledAsset(
            Data("upscale".utf8),
            fileExtension: "png",
            withSessionID: record.id
        )

        XCTAssertEqual(upscaled.preferredAssetURL, upscaled.upscaledAssetURL)
    }

    // MARK: - Helpers

    private func makeGraph() throws -> AssetGraph {
        AssetGraph(outputDirectory: try makeScratch())
    }

    /// Applies a filter to the current base and locks the result, returning the newly locked asset.
    private func applyFilterAndLock(_ graph: inout AssetGraph, name: String) throws -> AssetReference {
        let filtered = try graph.recordFilterOutput(
            of: try graph.input(for: .filter),
            fileURL: try placeholder(named: "\(name)-\(UUID().uuidString).png"),
            pixelSize: .fixture,
            filter: .fixture(id: name)
        )
        try graph.lock()
        return filtered
    }

    private func placeholder(named name: String) throws -> URL {
        let url = try scratchForPlaceholders().appendingPathComponent(name)
        try Data("placeholder".utf8).write(to: url)
        return url
    }

    private func scratchForPlaceholders() throws -> URL {
        if let existing = placeholderRoot { return existing }
        let created = try makeScratch()
        placeholderRoot = created
        return created
    }

    private var placeholderRoot: URL?

    /// A unique directory beneath the operating-system temporary directory, removed in teardown
    /// on success, on failure, and on handled interruption.
    private func makeScratch() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("superscale-assetgraph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }
        return root
    }
}

private extension CGSize {
    static let fixture = CGSize(width: 1024, height: 768)
    static let large = CGSize(width: 2048, height: 1536)
    static let larger = CGSize(width: 4096, height: 3072)
}

private extension FilterProvenance {
    static var fixture: FilterProvenance { fixture() }

    static func fixture(id: String = "warm", sessionID: UUID? = nil) -> FilterProvenance {
        FilterProvenance(
            filterID: id,
            modelID: "xai/grok-imagine-image/edit",
            prompt: "a fixture prompt",
            sessionID: sessionID,
            secrets: []
        )
    }
}

private extension GenerationSessionDraft {
    static var fixture: GenerationSessionDraft {
        GenerationSessionDraft(
            prompt: "fixture",
            modelID: "xai/grok-imagine-image/edit",
            estimatedCost: nil,
            referencePaths: [],
            timestamp: Date(timeIntervalSince1970: 100),
            status: .generated,
            safeDiagnostic: nil
        )
    }
}
