// ABOUTME: Verifies the store that makes toggling free: what it reuses, refuses, and evicts.
// ABOUTME: Holds identities rather than pixels, so nothing here writes a file.

import Foundation
import XCTest
@testable import SuperscaleUXCore

/// The rendering store.
///
/// A rendering is reusable exactly when the asset, the model, the sizing and the face setting all
/// match, so invalidation falls out of the key rather than being managed: applying a filter mints a
/// new asset identity, its renderings simply miss, and nothing still valid is discarded.
///
/// The store holds identities, not pixels. An 8-megapixel rendering is roughly 32 MB, and four of
/// them written per test would be unbounded output in a regression pack.
@MainActor
final class RenderingStoreTests: XCTestCase {

    private func key(
        asset: String = "base", model: String = "realesrgan-x4plus",
        sizing: String = "4x", faces: Bool = false
    ) -> RenderingKey {
        RenderingKey(assetID: asset, modelID: model, sizing: sizing, facesEnhanced: faces)
    }

    /// Counts how often it was asked to do the work, which is the thing being avoided.
    private final class Producer {
        private(set) var count = 0

        func produce(_ id: String) -> @Sendable () async throws -> RenderedImage {
            { [self] in
                count += 1
                return RenderedImage(id: id)
            }
        }
    }

    // MARK: - Reuse

    // RT-90.10
    func test_aRenderingAlreadyBuiltIsShownAgainWithoutBeingRebuilt_RT090_10() async throws {
        let store = RenderingStore()
        let producer = Producer()

        let first = try await store.rendering(for: key(), producedBy: producer.produce("up"))
        let second = try await store.rendering(for: key(), producedBy: producer.produce("up"))

        XCTAssertEqual(first, second)
        XCTAssertEqual(producer.count, 1, "the second ask cost nothing")
    }

    // RT-90.18
    func test_turningTheScaleOffAndOnAgainShowsTheUpscaleWithoutRebuilding_RT090_18() async throws {
        let store = RenderingStore()
        let producer = Producer()

        _ = try await store.rendering(for: key(), producedBy: producer.produce("up"))
        // Off: nothing is asked for, and nothing is discarded, because the key is still valid.
        _ = try await store.rendering(for: key(), producedBy: producer.produce("up"))

        XCTAssertEqual(producer.count, 1)
    }

    // RT-90.19
    func test_togglingFaceEnhancementOffAndOnAgainRebuildsNeither_RT090_19() async throws {
        let store = RenderingStore()
        let producer = Producer()

        _ = try await store.rendering(for: key(faces: false), producedBy: producer.produce("plain"))
        _ = try await store.rendering(for: key(faces: true), producedBy: producer.produce("faces"))
        _ = try await store.rendering(for: key(faces: false), producedBy: producer.produce("plain"))
        _ = try await store.rendering(for: key(faces: true), producedBy: producer.produce("faces"))

        XCTAssertEqual(producer.count, 2, "one production per version, not one per toggle")
    }

    // RT-90.11
    func test_theRebuildCountForTwoTogglesOfThePairIsOne_RT090_11() async throws {
        let store = RenderingStore()
        let producer = Producer()

        _ = try await store.rendering(for: key(faces: false), producedBy: producer.produce("plain"))
        _ = try await store.rendering(for: key(faces: true), producedBy: producer.produce("faces"))
        let countAfterBoth = producer.count

        _ = try await store.rendering(for: key(faces: false), producedBy: producer.produce("plain"))
        _ = try await store.rendering(for: key(faces: true), producedBy: producer.produce("faces"))

        XCTAssertEqual(producer.count - countAfterBoth, 0, "the second pass builds nothing")
    }

    // MARK: - Refusal

    // RT-90.20
    func test_aRenderingOfADifferentAssetIsNotOfferedForTheCurrentOne_RT090_20() async throws {
        let store = RenderingStore()
        let producer = Producer()

        let ofBase = try await store.rendering(
            for: key(asset: "base"), producedBy: producer.produce("base-up"))
        let ofCandidate = try await store.rendering(
            for: key(asset: "candidate"), producedBy: producer.produce("candidate-up"))

        XCTAssertNotEqual(ofBase, ofCandidate)
        XCTAssertEqual(producer.count, 2, "showing the wrong picture is worse than rebuilding")
    }

    // RT-90.21
    func test_aRenderingAtADifferentScaleIsNotOfferedForTheCurrentOne_RT090_21() async throws {
        let store = RenderingStore()
        let producer = Producer()

        _ = try await store.rendering(for: key(sizing: "2x"), producedBy: producer.produce("two"))
        let atFour = try await store.rendering(
            for: key(sizing: "4x"), producedBy: producer.produce("four"))

        XCTAssertEqual(atFour, RenderedImage(id: "four"))
        XCTAssertEqual(producer.count, 2)
    }

    // RT-90.29
    //
    // A failed operation contributes nothing, so the next ask tries again rather than serving a
    // hole. AC90.8 makes failure a designed state: #91 adds a memory cap that refuses work.
    func test_aFailedOperationContributesNoRendering_RT090_29() async throws {
        let store = RenderingStore()
        struct Refused: Error {}

        do {
            _ = try await store.rendering(for: key(), producedBy: { throw Refused() })
            XCTFail("the failure should propagate")
        } catch is Refused {
            // expected
        }

        let producer = Producer()
        let second = try await store.rendering(for: key(), producedBy: producer.produce("up"))

        XCTAssertEqual(second, RenderedImage(id: "up"))
        XCTAssertEqual(producer.count, 1, "the failure left nothing behind to serve")
    }

    // A rendering produced elsewhere is held on the same terms as one produced here, bound
    // included. Without this the Combine-driven caller would have a second, unbounded path in.
    func test_aRenderingAdmittedFromElsewhereIsHeldAndBounded() async throws {
        let store = RenderingStore()
        let producer = Producer()

        for index in 0..<6 {
            store.admit(RenderedImage(id: "r\(index)"), for: key(asset: "asset\(index)"))
        }

        XCTAssertEqual(store.count, RenderingStore.bound)
        XCTAssertEqual(store.held(for: key(asset: "asset5")), RenderedImage(id: "r5"))

        let reused = try await store.rendering(
            for: key(asset: "asset5"), producedBy: producer.produce("rebuilt"))
        XCTAssertEqual(reused, RenderedImage(id: "r5"))
        XCTAssertEqual(producer.count, 0, "what was admitted is what is served")
    }

    // MARK: - The bound

    // RT-90.22
    func test_noMoreThanFourRenderingsAreHeld_RT090_22() async throws {
        let store = RenderingStore()
        let producer = Producer()

        for index in 0..<6 {
            _ = try await store.rendering(
                for: key(asset: "asset\(index)"), producedBy: producer.produce("r\(index)"))
        }

        XCTAssertEqual(store.count, 4)
    }

    // RT-90.43
    func test_theLeastRecentlyUsedIsDroppedFirst_RT090_43() async throws {
        let store = RenderingStore()
        let producer = Producer()

        for index in 0..<4 {
            _ = try await store.rendering(
                for: key(asset: "asset\(index)"), producedBy: producer.produce("r\(index)"))
        }
        // Touch the oldest, making asset1 the least recently used.
        _ = try await store.rendering(for: key(asset: "asset0"), producedBy: producer.produce("r0"))
        _ = try await store.rendering(for: key(asset: "asset4"), producedBy: producer.produce("r4"))

        XCTAssertNotNil(store.held(for: key(asset: "asset0")), "recently used, so retained")
        XCTAssertNil(store.held(for: key(asset: "asset1")), "least recently used, so dropped")
    }

    // RT-90.42
    //
    // Four entries is exactly the base and candidate faces pairs, so in ordinary use the store is
    // full and the next admission would otherwise evict the picture the user is looking at. A
    // blank canvas is the defect this whole slice exists to remove.
    func test_theDisplayedRenderingIsNotEvicted_RT090_42() async throws {
        let store = RenderingStore()
        let producer = Producer()

        let displayed = key(asset: "onScreen")
        _ = try await store.rendering(for: displayed, producedBy: producer.produce("shown"))
        store.markDisplayed(displayed)

        // Fill and overflow with entries that are all more recently used than the displayed one.
        for index in 0..<5 {
            _ = try await store.rendering(
                for: key(asset: "other\(index)"), producedBy: producer.produce("o\(index)"))
        }

        XCTAssertEqual(
            store.held(for: displayed), RenderedImage(id: "shown"),
            "the picture on the canvas survives a full store")
    }

    // MARK: - AC90.5: the filter toggle costs nothing twice

    // RT-90.37, RT-90.38
    //
    // The author's report: *"toggle off/on 4x loses cached upscale"*, and the asymmetry that gave
    // it away — toggling **faces** was instant while toggling the **scale** rebuilt from scratch,
    // so the store was being consulted on one path and not the other.
    //
    // The filter toggle is the same shape one level up. Showing the base and then the candidate
    // again must offer both from the store, and must issue **no provider request** for the second
    // look: a filter result already in hand is a picture, not a reason to pay 2c again.
    func test_togglingTheFilterOffAndOnAgainRebuildsNeither_RT090_37() async throws {
        let store = RenderingStore()
        let producer = Producer()

        let base = key(asset: "base")
        let candidate = key(asset: "candidate")

        // Both looked at once.
        let firstBase = try await store.rendering(for: base, producedBy: producer.produce("b"))
        let firstCandidate = try await store.rendering(
            for: candidate, producedBy: producer.produce("c"))
        XCTAssertEqual(producer.count, 2, "one build each, to begin with")

        // Toggled off, and back on.
        let againBase = try await store.rendering(for: base, producedBy: producer.produce("b"))
        let againCandidate = try await store.rendering(
            for: candidate, producedBy: producer.produce("c"))

        // RT-90.38: nothing was built the second time. For the candidate that means no provider
        // request, because producing a filter result *is* a provider request.
        XCTAssertEqual(producer.count, 2, "the second look costs nothing")
        XCTAssertEqual(againBase, firstBase, "and shows the same picture")
        XCTAssertEqual(againCandidate, firstCandidate)
    }

    // RT-90.39
    //
    // A different filter replaces the preserved result rather than accumulating one. The key carries
    // the asset's identity, so a new filter result is a new asset and simply misses — which is what
    // makes invalidation fall out of the key rather than being managed. An implementation keying on
    // "the candidate" as a role rather than as an identity would serve the old picture for the new
    // filter, which is the worst available failure: a plausible, wrong image.
    func test_applyingADifferentFilterReplacesThePreservedResult_RT090_39() async throws {
        let store = RenderingStore()
        let producer = Producer()

        let noir = key(asset: "candidate-noir")
        let firstResult = try await store.rendering(for: noir, producedBy: producer.produce("noir"))
        store.markDisplayed(noir)

        let woodblock = key(asset: "candidate-woodblock")
        let secondResult = try await store.rendering(
            for: woodblock, producedBy: producer.produce("woodblock"))

        XCTAssertEqual(producer.count, 2, "a different filter is different work")
        XCTAssertNotEqual(secondResult, firstResult, "and a different picture")
        XCTAssertNil(
            store.held(for: key(asset: "candidate")),
            "there is no role-shaped entry for a later filter to collide with")
    }

    /// A new picture empties the store outright.
    ///
    /// Its predecessor's renderings describe something the user is no longer looking at, and an
    /// asset identity is only unique within a session's graph.
    func test_anewPictureEmptiesTheStore() async throws {
        let store = RenderingStore()
        let producer = Producer()
        let held = key(asset: "base")
        _ = try await store.rendering(for: held, producedBy: producer.produce("b"))

        store.forget()

        XCTAssertNil(store.held(for: held))
    }
}
