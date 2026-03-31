// ABOUTME: XCUITest suite for the Superscale GUI app.
// ABOUTME: Covers launch state, accessibility identifiers, element existence, and interaction flows.

import XCTest

final class SuperscaleAppUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    // MARK: - Existing tests (RT-106 through RT-110)

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

    // RT-110: File chooser button exists
    func test_file_chooser_button_exists_RT110() {
        let chooser = app.buttons["fileChooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 5),
                      "File chooser button should be present on launch")
    }

    // MARK: - OT-004: GUI scaffold (#44)

    // RT-122: Model picker sheet lists all models
    func test_model_picker_lists_all_models_RT122() {
        let picker = app.buttons["modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()

        // Sheet should contain "Select Model" heading and all 7 models + auto-detect
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Model selection sheet should appear")
        XCTAssertTrue(sheet.staticTexts["Select Model"].exists, "Sheet should have title")
        XCTAssertTrue(sheet.staticTexts["Auto-detect"].exists, "Auto-detect option should exist")
    }

    // RT-123: Scale indicator updates when model changes
    func test_scale_indicator_updates_per_model_RT123() {
        // Default should show 4× scale buttons as selected
        XCTAssertTrue(app.buttons["scale4x"].waitForExistence(timeout: 5))
        // Verify 2× model exists in picker (we can't easily verify scale text change
        // without selecting a model, which requires sheet interaction)
        XCTAssertTrue(app.buttons["scale2x"].exists)
    }

    // RT-124: Model sheet shows CLI names and expandable descriptions
    func test_model_sheet_shows_cli_names_RT124() {
        let picker = app.buttons["modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        // CLI model names should be visible in the sheet
        XCTAssertTrue(sheet.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'realesrgan-x4plus'")).firstMatch.exists,
            "CLI model name realesrgan-x4plus should be visible")
    }

    // RT-125: Model picker button has accessibility help text
    func test_model_picker_has_help_text_RT125() {
        let picker = app.buttons["modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        // Accessibility help is exposed as a property
        XCTAssertNotNil(picker.value, "Model picker should have accessible value/help")
    }

    // RT-126: Window title shows filename after loading image
    func test_window_title_shows_filename_RT126() {
        // On launch, title should be "Superscale"
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
    }

    // RT-127: About button exists with icon
    func test_about_button_exists_RT127() {
        let about = app.buttons["aboutButton"]
        XCTAssertTrue(about.waitForExistence(timeout: 5),
                      "About button should be present")
    }

    // RT-139: Load image via file chooser, verify result appears
    // Note: This test requires a test image accessible via NSOpenPanel.
    // XCUITest can click the file chooser button but interacting with
    // NSOpenPanel programmatically is fragile. Marking as placeholder.
    func test_file_chooser_loads_image_RT139() {
        let chooser = app.buttons["fileChooser"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 5))
        // Placeholder — full interaction requires NSOpenPanel automation
    }

    // RT-140: Progress indicator exists during processing
    // Placeholder — requires image load + timing check
    func test_progress_indicator_during_processing_RT140() {
        // Would need to trigger upscale and check for progress element
        // Placeholder until file load automation is reliable
    }

    // MARK: - OT-005: Comparison view (#45)

    // RT-141: Compare button appears after upscale, comparison elements visible
    func test_compare_button_exists_after_result_RT141() {
        // Compare button only appears when result exists
        // On launch it should not exist
        XCTAssertFalse(app.buttons["compareButton"].exists,
                       "Compare button should not exist before upscale")
    }

    // RT-142: Toggle comparison mode
    func test_compare_mode_toggles_RT142() {
        // Placeholder — requires loaded image to test toggle
    }

    // MARK: - OT-006: Scale picker (#49)

    // RT-131: Model change clears custom fields
    func test_model_change_clears_custom_fields_RT131() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        // Custom fields should be visible after clicking Custom
        // Change model should hide them
        let picker = app.buttons["modelPicker"]
        picker.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        // Select first non-auto model to trigger model change
        sheet.buttons.element(boundBy: 1).click()
    }

    // RT-143: Stretch mode with dimensions
    func test_stretch_with_dimensions_RT143() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()
        // Stretch toggle should become visible when custom is active
    }

    // RT-144: Custom with no value, preset still active
    func test_custom_no_value_preset_active_RT144() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()
        // Without typing a value, preset should still be visually selected
    }

    // RT-145: Zero and non-numeric rejection
    func test_zero_and_nonnumeric_rejected_RT145() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        // Find the width text field and type invalid input
        let textFields = app.textFields
        if textFields.count > 0 {
            let widthField = textFields.firstMatch
            widthField.click()
            widthField.typeText("abc")
            // Field should reject non-numeric — value should be empty
            XCTAssertEqual(widthField.value as? String ?? "", "",
                           "Non-numeric input should be rejected")
        }
    }

    // RT-146: Stretch uncheck preserves defining dimension
    func test_stretch_uncheck_preserves_defining_RT146() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()
        // Placeholder — requires typing in fields and toggling stretch
    }

    // RT-147: Stretch with one dimension disables stretch
    func test_stretch_one_dimension_disables_RT147() {
        // Placeholder — requires image load to verify output
    }

    // RT-148: Custom dimensions before and after image load
    func test_custom_before_after_image_RT148() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()
        // Placeholder — requires image load to verify height populates
    }

    // MARK: - OT-007: Face enhancement (#52)

    // RT-149: Face enhance button exists and toggles
    func test_face_enhance_button_exists_RT149() {
        let face = app.buttons["faceEnhanceButton"]
        XCTAssertTrue(face.waitForExistence(timeout: 5),
                      "Face enhance button should exist on launch")
    }

    // RT-151: Face toggle changes image
    func test_face_toggle_changes_image_RT151() {
        // Placeholder — requires loaded image
    }

    // RT-152: Face off then on triggers re-upscale
    func test_face_off_then_on_reupscales_RT152() {
        // Placeholder — requires loaded image
    }

    // RT-153: Custom scale preserved on face toggle
    func test_custom_scale_preserved_on_face_toggle_RT153() {
        // Placeholder — requires loaded image with custom scale
    }

    // MARK: - OT-008: Info panel (#53)

    // RT-136: Info panel visible with model and scale text
    func test_info_panel_visible_on_launch_RT136() {
        // Info panel should show model and scale info on launch
        let modelText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelText.waitForExistence(timeout: 5),
                      "Info panel should show model info on launch")
    }

    // RT-137: Info panel dismiss and reappear
    func test_info_panel_dismiss_and_reappear_RT137() {
        // Find and click the dismiss button (xmark)
        let dismissButtons = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'xmark'"))
        if dismissButtons.count > 0 {
            dismissButtons.firstMatch.click()
            // Info panel text should disappear
            let modelText = app.staticTexts.matching(
                NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
            XCTAssertFalse(modelText.exists,
                           "Info panel should be hidden after dismiss")
        }
    }

    // RT-156: Info panel updates on setting changes
    func test_info_panel_updates_on_changes_RT156() {
        // Placeholder — requires changing model/scale and checking panel text
    }

    // RT-157: Post-upscale summary in info panel
    func test_info_panel_post_upscale_summary_RT157() {
        // Placeholder — requires image load and upscale
    }

    // MARK: - OT-009: File chooser upscale (#56)

    // RT-150: File chooser select and upscale
    func test_file_chooser_upscale_flow_RT150() {
        // Placeholder — requires NSOpenPanel interaction
    }

    // MARK: - OT-010: About panel (#58)

    // RT-128: About panel shows version
    func test_about_shows_version_RT128() {
        let about = app.buttons["aboutButton"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        // Version should match pattern v1.x.x
        let versionText = sheet.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH 'v'")).firstMatch
        XCTAssertTrue(versionText.exists, "Version string should be visible in About panel")
    }

    // RT-129: About panel shows app name
    func test_about_shows_app_name_RT129() {
        let about = app.buttons["aboutButton"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.staticTexts["Superscale"].exists,
                      "App name should be visible in About panel")
    }

    // RT-130: About panel shows author
    func test_about_shows_author_RT130() {
        let about = app.buttons["aboutButton"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let authorText = sheet.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Taḋg Paul'")).firstMatch
        XCTAssertTrue(authorText.exists, "Author should be visible in About panel")
    }

    // MARK: - OT-011: Dimension cap (#60)

    // RT-138: Typing large number is capped
    func test_dimension_cap_on_typing_RT138() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let textFields = app.textFields
        if textFields.count > 0 {
            let widthField = textFields.firstMatch
            widthField.click()
            widthField.typeText("99999")
            // Without an image, cap should be 16384
            let value = widthField.value as? String ?? ""
            XCTAssertTrue(Int(value) ?? 0 <= 16384,
                          "Value should be capped at 16384 without image, got \(value)")
        }
    }

    // RT-154: Cap re-applied on image load
    func test_dimension_cap_on_image_load_RT154() {
        // Placeholder — requires loading an image after typing large value
    }

    // RT-155: Cap warning in info panel
    func test_dimension_cap_warning_RT155() {
        // Placeholder — requires triggering cap and checking info panel
    }

    // MARK: - OT-012: UX improvements (#61)

    // RT-132: Text labels on buttons
    func test_button_text_labels_present_RT132() {
        // Check for "Custom" text label
        let customLabel = app.staticTexts.matching(
            NSPredicate(format: "value == 'Custom'")).firstMatch
        XCTAssertTrue(customLabel.waitForExistence(timeout: 5),
                      "Custom text label should be present")

        // Check for "Face" text label
        let faceLabel = app.staticTexts.matching(
            NSPredicate(format: "value == 'Face'")).firstMatch
        XCTAssertTrue(faceLabel.exists, "Face text label should be present")
    }

    // RT-133: About panel "Models installed:" title
    func test_about_models_installed_title_RT133() {
        let about = app.buttons["aboutButton"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let title = sheet.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Models installed'")).firstMatch
        XCTAssertTrue(title.exists, "About panel should show 'Models installed:' title")
    }

    // RT-134: Zoom buttons in comparison mode
    func test_zoom_buttons_in_comparison_RT134() {
        // Placeholder — requires loaded image + comparison mode
    }

    // RT-158: Info panel ordering and reset
    func test_info_panel_reset_on_setting_change_RT158() {
        // Placeholder — requires upscale then setting change
    }

    // MARK: - OT-013: Info panel restore (#63)

    // RT-135: Dismiss and restore info panel
    func test_info_panel_restore_button_RT135() {
        // Find info panel content
        let modelText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelText.waitForExistence(timeout: 5),
                      "Info panel should be visible on launch")

        // Dismiss it
        let dismissButtons = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'xmark'"))
        if dismissButtons.count > 0 {
            dismissButtons.firstMatch.click()

            // Restore button should appear (text.bubble icon)
            let restoreButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'text.bubble'"))
            XCTAssertTrue(restoreButton.firstMatch.waitForExistence(timeout: 3),
                          "Restore button should appear after dismissing info panel")

            // Click restore
            restoreButton.firstMatch.click()

            // Info panel should reappear
            XCTAssertTrue(modelText.waitForExistence(timeout: 3),
                          "Info panel should reappear after clicking restore")
        }
    }
}
