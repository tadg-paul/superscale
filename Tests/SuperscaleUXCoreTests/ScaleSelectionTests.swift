// ABOUTME: Verifies the scale control behaves as a toggle group with a genuine off state.
// ABOUTME: Covers the selection transitions and the paths that must not resurrect a cleared one.

import Foundation
import XCTest
@testable import SuperscaleUXCore

final class ScaleSelectionTests: XCTestCase {

    // MARK: - AC82.7 the toggle group

    // RT-82.18
    func test_choosingTheActivePresetClearsTheSelection() {
        let selection = ScaleSelection.preset(4)

        XCTAssertEqual(selection.choosing(.preset(4)), .off)
    }

    // RT-82.19
    func test_choosingADifferentPresetSelectsThatOne() {
        let selection = ScaleSelection.preset(4)

        XCTAssertEqual(selection.choosing(.preset(8)), .preset(8))
    }

    // RT-82.20
    func test_choosingTheActiveCustomOptionClearsTheSelection() {
        let selection = ScaleSelection.custom

        XCTAssertEqual(selection.choosing(.custom), .off)
    }

    // RT-82.21
    func test_withNothingSelectedNoChoiceReportsItselfActive() {
        let selection = ScaleSelection.off

        XCTAssertFalse(selection.isActive(.preset(2)))
        XCTAssertFalse(selection.isActive(.preset(4)))
        XCTAssertFalse(selection.isActive(.preset(8)))
        XCTAssertFalse(selection.isActive(.custom))
    }

    // RT-82.32
    func test_choosingCustomMakesItActiveBeforeAnyDimensionIsTyped() {
        let selection = ScaleSelection.preset(4).choosing(.custom)

        XCTAssertEqual(selection, .custom)
        XCTAssertTrue(selection.isActive(.custom))
        XCTAssertFalse(selection.isActive(.preset(4)))
    }

    // RT-82.30
    func test_typedDimensionsSurviveTheSelectionBeingClearedAndRestored() {
        var settings = UpscaleRunSettings.fixture
        settings.selection = .custom
        settings.customWidth = 1600
        settings.customHeight = 1200

        settings.choose(.custom)
        XCTAssertEqual(settings.selection, .off)

        settings.choose(.custom)

        XCTAssertEqual(settings.selection, .custom)
        XCTAssertEqual(settings.customWidth, 1600)
        XCTAssertEqual(settings.customHeight, 1200)
    }

    // MARK: - AC82.8 a cleared selection persists

    // RT-82.22
    func test_importingAnImageWhileTheSelectionIsClearedLeavesItCleared() {
        var settings = UpscaleRunSettings.fixture
        settings.selection = .off

        settings.adoptNativeScale(4)

        XCTAssertEqual(settings.selection, .off)
    }

    // RT-82.23
    func test_changingTheModelWhileTheSelectionIsClearedLeavesItCleared() {
        var settings = UpscaleRunSettings.fixture
        settings.selection = .off

        settings.setModel(named: "realesrgan-x2plus", nativeScale: 2)

        XCTAssertEqual(settings.selection, .off)
        XCTAssertEqual(settings.modelName, "realesrgan-x2plus")
    }

    // RT-82.24
    func test_changingTheCustomDimensionTextNeverCreatesASelection() {
        var settings = UpscaleRunSettings.fixture
        settings.selection = .off

        settings.setCustomDimensions(width: 2000, height: nil)

        XCTAssertEqual(settings.selection, .off)
        XCTAssertEqual(settings.customWidth, 2000)
    }

    // RT-82.25
    func test_importingAnImageWhileAScaleIsSelectedAdoptsTheModelsNativeScale() {
        var settings = UpscaleRunSettings.fixture
        settings.selection = .preset(8)

        settings.adoptNativeScale(4)

        XCTAssertEqual(settings.selection, .preset(4))
    }

    // A selected scale is replaced by the model's native scale, not cleared by it.
    // Guards the same boundary as RT-82.25 from the model-change side.
    func test_changingTheModelWhileAScaleIsSelectedAdoptsItsNativeScale() {
        var settings = UpscaleRunSettings.fixture
        settings.selection = .preset(8)

        settings.setModel(named: "realesrgan-x2plus", nativeScale: 2)

        XCTAssertEqual(settings.selection, .preset(2))
    }
}

extension UpscaleRunSettings {
    static var fixture: UpscaleRunSettings {
        UpscaleRunSettings(
            selection: .preset(4),
            modelName: "auto",
            faceEnhance: false,
            customWidth: nil,
            customHeight: nil,
            stretch: false
        )
    }
}
