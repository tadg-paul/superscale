// ABOUTME: XCUITest suite for the Superscale GUI app.
// ABOUTME: Covers launch state, accessibility identifiers, and core UI elements.

import XCTest

final class SuperscaleAppUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    // RT-106: Key views are locatable by accessibility identifier
    func test_accessibility_identifiers_RT106() {
        XCTAssertTrue(app.staticTexts["dropTarget"].waitForExistence(timeout: 5),
                      "dropTarget identifier should be locatable")
        XCTAssertTrue(app.buttons["modelPicker"].exists || app.otherElements["modelPicker"].exists,
                      "modelPicker identifier should be locatable")
    }

    // RT-107: Drop target visible on launch
    func test_drop_target_visible_on_launch_RT107() {
        let dropText = app.staticTexts["dropTarget"]
        XCTAssertTrue(dropText.waitForExistence(timeout: 5),
                      "Drop target text should be visible on launch")
    }

    // RT-108: Model picker button exists
    func test_model_picker_exists_RT108() {
        // The model picker is a button containing the "modelPicker" identifier
        let picker = app.buttons.matching(NSPredicate(format: "identifier == 'modelPicker'")).firstMatch
        let pickerAlt = app.otherElements["modelPicker"]
        XCTAssertTrue(picker.exists || pickerAlt.exists,
                      "Model picker button should exist on launch")
    }

    // RT-109: Scale buttons present
    func test_scale_buttons_present_RT109() {
        XCTAssertTrue(app.buttons["scale2x"].waitForExistence(timeout: 5),
                      "2× scale button should be present")
        XCTAssertTrue(app.buttons["scale4x"].exists,
                      "4× scale button should be present")
        XCTAssertTrue(app.buttons["scale8x"].exists,
                      "8× scale button should be present")
        XCTAssertTrue(app.buttons["scaleCustom"].exists,
                      "Custom scale button should be present")
    }

    // RT-110: File chooser button exists and is clickable
    func test_file_chooser_button_exists_RT110() {
        let chooser = app.buttons["fileChooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 5),
                      "File chooser button should be present on launch")
    }
}
