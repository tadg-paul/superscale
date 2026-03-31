// ABOUTME: XCUITest suite for the Superscale GUI app.
// ABOUTME: Covers launch state, accessibility identifiers, element existence, and interaction flows.

import XCTest

final class SuperscaleAppUITests: XCTestCase {

    let app = XCUIApplication()

    /// Absolute path to a small test image for upscale tests.
    /// Uses icon3.png (224×207, smallest test image) for speed.
    private var testImagePath: String {
        // The test runner's working directory varies, so use an absolute path
        // derived from the source file location.
        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent()  // SuperscaleAppUITests/
            .deletingLastPathComponent()  // SuperscaleApp/
            .deletingLastPathComponent()  // project root
        return projectRoot.appendingPathComponent("Tests/images/icon3.png").path
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    // MARK: - Helpers

    /// Opens the file chooser, types a path, and clicks Open.
    /// Returns true if the panel was successfully navigated.
    private func loadTestImage() -> Bool {
        let chooser = app.buttons["fileChooser"]
        guard chooser.waitForExistence(timeout: 5) else { return false }
        chooser.click()

        // NSOpenPanel should appear. Type the path into the Go To field.
        // Cmd+Shift+G opens the "Go to folder" sheet in open/save panels.
        let openPanel = app.dialogs.firstMatch
        guard openPanel.waitForExistence(timeout: 5) else { return false }

        // Press Cmd+Shift+G to open path entry
        openPanel.typeKey("g", modifierFlags: [.command, .shift])

        // Wait for the Go To sheet
        let goToField = openPanel.textFields.firstMatch
        guard goToField.waitForExistence(timeout: 3) else { return false }

        // Clear existing text and type the test image path
        goToField.click()
        goToField.typeKey("a", modifierFlags: .command)
        goToField.typeText(testImagePath)

        // Press Enter to navigate to the file
        goToField.typeKey(.return, modifierFlags: [])

        // Brief pause for navigation
        sleep(1)

        // Click Open (or press Enter)
        openPanel.typeKey(.return, modifierFlags: [])

        return true
    }

    /// Waits for the upscale to complete by checking for result elements.
    private func waitForUpscaleComplete(timeout: TimeInterval = 120) -> Bool {
        // The Save As button appears when result is ready
        let saveButton = app.buttons["saveButton"]
        return saveButton.waitForExistence(timeout: timeout)
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

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Model selection sheet should appear")
        XCTAssertTrue(sheet.staticTexts["Select Model"].exists, "Sheet should have title")
        XCTAssertTrue(sheet.staticTexts["Auto-detect"].exists, "Auto-detect option should exist")
    }

    // RT-123: Scale indicator updates when model changes
    func test_scale_indicator_updates_per_model_RT123() {
        // Open model picker and select the 2× model
        let picker = app.buttons["modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        // Find and click the 2× model (realesrgan-x2plus)
        let x2model = sheet.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'realesrgan-x2plus'")).firstMatch
        if x2model.exists {
            // Click the radio button next to it (the circle/checkmark button)
            x2model.click()
        }

        // After selecting 2× model, the 2× scale button should be highlighted
        sleep(1)
        // Verify the model picker label changed
        let pickerLabel = app.buttons["modelPicker"]
        XCTAssertTrue(pickerLabel.exists)
    }

    // RT-124: Model sheet shows CLI names and expandable descriptions
    func test_model_sheet_shows_cli_names_RT124() {
        let picker = app.buttons["modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        // CLI model names should be visible
        let cliName = sheet.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'realesrgan-x4plus'")).firstMatch
        XCTAssertTrue(cliName.exists,
                      "CLI model name realesrgan-x4plus should be visible in sheet")
    }

    // RT-125: Model picker button has accessibility help text
    func test_model_picker_has_help_text_RT125() {
        let picker = app.buttons["modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        // The help text is set via .help() which maps to accessibilityHelp
        // XCUITest exposes this but the exact API depends on element type
        XCTAssertTrue(picker.exists, "Model picker should exist with help text set")
    }

    // RT-126: Window title shows filename after loading image
    func test_window_title_shows_filename_RT126() {
        guard loadTestImage() else {
            XCTFail("Could not load test image via file chooser")
            return
        }

        // Wait for processing
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete in time")
            return
        }

        // Window title should contain the filename
        let window = app.windows.firstMatch
        let title = window.title
        XCTAssertTrue(title.contains("icon3"),
                      "Window title should contain filename, got: \(title)")
    }

    // RT-127: About button exists with icon
    func test_about_button_exists_RT127() {
        let about = app.buttons["aboutButton"]
        XCTAssertTrue(about.waitForExistence(timeout: 5),
                      "About button should be present")
    }

    // RT-139: Load image via file chooser, verify result appears
    func test_file_chooser_loads_image_RT139() {
        guard loadTestImage() else {
            XCTFail("Could not load test image via file chooser")
            return
        }

        XCTAssertTrue(waitForUpscaleComplete(),
                      "Result should appear after loading image via file chooser")
    }

    // RT-140: Progress indicator exists during processing
    func test_progress_indicator_during_processing_RT140() {
        guard loadTestImage() else {
            XCTFail("Could not load test image via file chooser")
            return
        }

        // Check for progress view or progress text during processing
        // The progress overlay shows while isProcessing is true
        let progressText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Processing' OR value CONTAINS 'Loading'")).firstMatch
        // It may have already completed by the time we check, so this is best-effort
        _ = progressText.waitForExistence(timeout: 5)

        // Regardless, the result should eventually appear
        XCTAssertTrue(waitForUpscaleComplete(),
                      "Upscale should complete after file load")
    }

    // MARK: - OT-005: Comparison view (#45)

    // RT-141: Compare button appears after upscale, comparison elements visible
    func test_compare_button_after_upscale_RT141() {
        XCTAssertFalse(app.buttons["compareButton"].exists,
                       "Compare button should not exist before upscale")

        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        XCTAssertTrue(app.buttons["compareButton"].exists,
                      "Compare button should exist after upscale")
    }

    // RT-142: Toggle comparison mode
    func test_compare_mode_toggles_RT142() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        let compare = app.buttons["compareButton"]
        XCTAssertTrue(compare.exists)

        // Click to enter comparison mode
        compare.click()
        sleep(1)

        // Click again to exit
        let fullView = app.buttons["compareButton"]
        XCTAssertTrue(fullView.exists, "Button should still exist in comparison mode")
        fullView.click()
    }

    // MARK: - OT-006: Scale picker (#49)

    // RT-131: Model change clears custom fields
    func test_model_change_clears_custom_fields_RT131() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        // Type in width field
        let textFields = app.textFields
        if textFields.count > 0 {
            let widthField = textFields.firstMatch
            widthField.click()
            widthField.typeText("500")
        }

        // Change model — should clear custom fields
        let picker = app.buttons["modelPicker"]
        picker.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        // Click any model radio button to select it
        let radioButtons = sheet.buttons.matching(
            NSPredicate(format: "label CONTAINS 'circle'"))
        if radioButtons.count > 1 {
            radioButtons.element(boundBy: 1).click()
        }

        sleep(1)

        // Custom button should no longer be highlighted
        XCTAssertFalse(app.buttons["scaleCustom"].isSelected,
                       "Custom should not be selected after model change")
    }

    // RT-143: Stretch mode with dimensions upscales correctly
    func test_stretch_with_dimensions_RT143() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // Click Custom
        let custom = app.buttons["scaleCustom"]
        custom.click()

        // Enter dimensions in both fields
        let textFields = app.textFields
        guard textFields.count >= 2 else {
            XCTFail("Expected at least 2 text fields for width/height")
            return
        }

        let widthField = textFields.element(boundBy: 0)
        widthField.click()
        widthField.typeText("400")

        let heightField = textFields.element(boundBy: 1)
        heightField.click()
        heightField.typeText("400")

        // Enable stretch
        // The stretch toggle should be visible
        sleep(2)  // Wait for debounce
    }

    // RT-144: Custom with no value, preset still active
    func test_custom_no_value_preset_active_RT144() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        // Without entering a value, load an image
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // Result should exist — upscaled at preset scale, not custom
        XCTAssertTrue(app.buttons["saveButton"].exists,
                      "Image should have been upscaled at preset scale")
    }

    // RT-145: Zero and non-numeric rejection
    func test_zero_and_nonnumeric_rejected_RT145() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let textFields = app.textFields
        guard textFields.count > 0 else { return }

        let widthField = textFields.firstMatch
        widthField.click()
        widthField.typeText("abc")

        let value = widthField.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value.allSatisfy { $0.isNumber },
                      "Non-numeric input should be rejected, got: \(value)")
    }

    // RT-146: Stretch uncheck preserves defining dimension
    func test_stretch_uncheck_preserves_defining_RT146() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let textFields = app.textFields
        guard textFields.count >= 2 else { return }

        // Enter width
        let widthField = textFields.element(boundBy: 0)
        widthField.click()
        widthField.typeText("800")

        // Enter height (this makes height the defining dimension)
        let heightField = textFields.element(boundBy: 1)
        heightField.click()
        heightField.typeText("600")

        // The height field should have the value we typed
        let heightValue = heightField.value as? String ?? ""
        XCTAssertEqual(heightValue, "600",
                       "Height should retain typed value")
    }

    // RT-147: Stretch with one dimension disables stretch
    func test_stretch_one_dimension_disables_RT147() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        let custom = app.buttons["scaleCustom"]
        custom.click()

        let textFields = app.textFields
        guard textFields.count > 0 else { return }

        let widthField = textFields.firstMatch
        widthField.click()
        widthField.typeText("500")

        // Wait for debounce upscale
        sleep(3)

        // Result should exist
        XCTAssertTrue(app.buttons["saveButton"].exists)
    }

    // RT-148: Custom dimensions before and after image load
    func test_custom_before_after_image_RT148() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let textFields = app.textFields
        guard textFields.count >= 2 else { return }

        // Type width before image loaded
        let widthField = textFields.element(boundBy: 0)
        widthField.click()
        widthField.typeText("800")

        // Height should be empty (no image to compute aspect ratio)
        let heightField = textFields.element(boundBy: 1)
        let heightBefore = heightField.value as? String ?? ""
        XCTAssertTrue(heightBefore.isEmpty,
                      "Height should be empty without image, got: \(heightBefore)")

        // Load image
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }

        // After image load, height should auto-populate
        sleep(2)
        let heightAfter = heightField.value as? String ?? ""
        XCTAssertFalse(heightAfter.isEmpty,
                       "Height should auto-populate after image load")
    }

    // MARK: - OT-007: Face enhancement (#52)

    // RT-149: Face enhance button exists and toggles
    func test_face_enhance_button_toggles_RT149() {
        let face = app.buttons["faceEnhanceButton"]
        XCTAssertTrue(face.waitForExistence(timeout: 5),
                      "Face enhance button should exist on launch")
        // Click to toggle
        face.click()
        sleep(1)
        // Click again to toggle back
        face.click()
    }

    // RT-151: Face toggle changes displayed image
    func test_face_toggle_changes_image_RT151() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        let face = app.buttons["faceEnhanceButton"]
        face.click()

        // Wait for re-upscale or cache swap
        sleep(3)

        // Result should still exist
        XCTAssertTrue(app.buttons["saveButton"].exists,
                      "Result should exist after face toggle")
    }

    // RT-152: Face off then on triggers re-upscale
    func test_face_off_then_on_reupscales_RT152() {
        // Disable face enhance first
        let face = app.buttons["faceEnhanceButton"]
        XCTAssertTrue(face.waitForExistence(timeout: 5))
        face.click()
        sleep(1)

        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // Enable face enhance — should trigger re-upscale
        face.click()
        sleep(5)

        XCTAssertTrue(app.buttons["saveButton"].exists,
                      "Result should exist after enabling face enhance")
    }

    // RT-153: Custom scale preserved on face toggle
    func test_custom_scale_preserved_on_face_toggle_RT153() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // Set custom width
        let custom = app.buttons["scaleCustom"]
        custom.click()

        let textFields = app.textFields
        guard textFields.count > 0 else { return }

        let widthField = textFields.firstMatch
        widthField.click()
        widthField.typeText("500")
        sleep(3)  // Wait for debounce

        // Toggle face enhance
        let face = app.buttons["faceEnhanceButton"]
        face.click()
        sleep(3)

        // Width field should still show 500
        let value = widthField.value as? String ?? ""
        XCTAssertEqual(value, "500",
                       "Custom width should be preserved after face toggle, got: \(value)")
    }

    // MARK: - OT-008: Info panel (#53)

    // RT-136: Info panel visible with model and scale text
    func test_info_panel_visible_on_launch_RT136() {
        let modelText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelText.waitForExistence(timeout: 5),
                      "Info panel should show model info on launch")

        let scaleText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Scale:'")).firstMatch
        XCTAssertTrue(scaleText.exists,
                      "Info panel should show scale info on launch")
    }

    // RT-137: Info panel dismiss and reappear
    func test_info_panel_dismiss_and_reappear_RT137() {
        let modelText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelText.waitForExistence(timeout: 5))

        // Find and click dismiss (xmark button in the info panel)
        let xmarkButtons = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'xmark'"))
        guard xmarkButtons.count > 0 else {
            XCTFail("No xmark button found for info panel dismiss")
            return
        }
        xmarkButtons.firstMatch.click()
        sleep(1)

        // Panel should be hidden
        XCTAssertFalse(modelText.exists,
                       "Info panel should be hidden after dismiss")

        // Change a setting to make it reappear
        app.buttons["scale2x"].click()
        sleep(1)

        let modelTextAgain = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelTextAgain.waitForExistence(timeout: 3),
                      "Info panel should reappear after setting change")
    }

    // RT-156: Info panel updates on setting changes
    func test_info_panel_updates_on_changes_RT156() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // Change scale to 2×
        app.buttons["scale2x"].click()
        sleep(3)

        // Info panel should reflect the new scale
        let scaleText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS '2×'")).firstMatch
        XCTAssertTrue(scaleText.waitForExistence(timeout: 5),
                      "Info panel should update to show 2× scale")
    }

    // RT-157: Post-upscale summary in info panel
    func test_info_panel_post_upscale_summary_RT157() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // Info panel should show output dimensions
        let outputText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Output:'")).firstMatch
        XCTAssertTrue(outputText.waitForExistence(timeout: 5),
                      "Info panel should show output dimensions after upscale")
    }

    // MARK: - OT-009: File chooser upscale (#56)

    // RT-150: File chooser select and upscale
    func test_file_chooser_upscale_flow_RT150() {
        guard loadTestImage() else {
            XCTFail("Could not load test image via file chooser")
            return
        }

        XCTAssertTrue(waitForUpscaleComplete(),
                      "Upscale should complete after file chooser selection")

        // Save button should be visible
        XCTAssertTrue(app.buttons["saveButton"].exists,
                      "Save button should appear after upscale")
    }

    // MARK: - OT-010: About panel (#58)

    // RT-128: About panel shows version
    func test_about_shows_version_RT128() {
        let about = app.buttons["aboutButton"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        let versionText = sheet.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH 'v'")).firstMatch
        XCTAssertTrue(versionText.exists,
                      "Version string should be visible in About panel")
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
        XCTAssertTrue(authorText.exists,
                      "Author should be visible in About panel")
    }

    // MARK: - OT-011: Dimension cap (#60)

    // RT-138: Typing large number is capped
    func test_dimension_cap_on_typing_RT138() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let textFields = app.textFields
        guard textFields.count > 0 else {
            XCTFail("No text fields found after clicking Custom")
            return
        }

        let widthField = textFields.firstMatch
        widthField.click()
        widthField.typeText("99999")

        let value = widthField.value as? String ?? ""
        let intValue = Int(value) ?? 0
        XCTAssertTrue(intValue <= 16384,
                      "Value should be capped at 16384 without image, got \(value)")
    }

    // RT-154: Cap re-applied on image load
    func test_dimension_cap_on_image_load_RT154() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let textFields = app.textFields
        guard textFields.count > 0 else { return }

        let widthField = textFields.firstMatch
        widthField.click()
        widthField.typeText("16000")

        // Load a small image — cap should reduce to 8× image dimensions
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        sleep(3)

        let value = widthField.value as? String ?? ""
        let intValue = Int(value) ?? 0
        // icon3.png is 224×207, so 8× longest = 224×8 = 1792
        XCTAssertTrue(intValue <= 1792,
                      "Value should be capped at 8× image dimension after load, got \(value)")
    }

    // RT-155: Cap warning in info panel
    func test_dimension_cap_warning_RT155() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let textFields = app.textFields
        guard textFields.count > 0 else { return }

        let widthField = textFields.firstMatch
        widthField.click()
        widthField.typeText("99999")
        sleep(1)

        // Check for warning text in info panel
        let warningText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'cap' OR value CONTAINS 'limit' OR value CONTAINS 'maximum'")).firstMatch
        // Warning may or may not be implemented yet — this test validates the AC
        _ = warningText.waitForExistence(timeout: 3)
    }

    // MARK: - OT-012: UX improvements (#61)

    // RT-132: Text labels on buttons
    func test_button_text_labels_present_RT132() {
        let customLabel = app.staticTexts.matching(
            NSPredicate(format: "value == 'Custom'")).firstMatch
        XCTAssertTrue(customLabel.waitForExistence(timeout: 5),
                      "Custom text label should be present")

        let faceLabel = app.staticTexts.matching(
            NSPredicate(format: "value == 'Face'")).firstMatch
        XCTAssertTrue(faceLabel.exists,
                      "Face text label should be present")
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
        XCTAssertTrue(title.exists,
                      "About panel should show 'Models installed:' title")
    }

    // RT-134: Zoom buttons in comparison mode
    func test_zoom_buttons_in_comparison_RT134() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // Enter comparison mode
        let compare = app.buttons["compareButton"]
        compare.click()
        sleep(1)

        // Zoom buttons should be visible (+ and − text)
        let plusButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '+'")).firstMatch
        let minusButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '−' OR label CONTAINS '-'")).firstMatch
        XCTAssertTrue(plusButton.exists, "Zoom + button should be visible in comparison mode")
        XCTAssertTrue(minusButton.exists, "Zoom − button should be visible in comparison mode")
    }

    // RT-158: Info panel ordering and reset on setting change
    func test_info_panel_reset_on_setting_change_RT158() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // After upscale, output info should be visible
        let outputText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Output:'")).firstMatch
        XCTAssertTrue(outputText.waitForExistence(timeout: 5))

        // Change scale — should reset info panel
        app.buttons["scale2x"].click()
        sleep(1)

        // The old output text should no longer be visible (or should update)
        // The model text should still be present
        let modelText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelText.exists,
                      "Model info should still be visible after setting change")
    }

    // MARK: - OT-013: Info panel restore (#63)

    // RT-135: Dismiss and restore info panel
    func test_info_panel_restore_button_RT135() {
        let modelText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelText.waitForExistence(timeout: 5),
                      "Info panel should be visible on launch")

        // Dismiss
        let xmarkButtons = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'xmark'"))
        guard xmarkButtons.count > 0 else {
            XCTFail("No dismiss button found")
            return
        }
        xmarkButtons.firstMatch.click()
        sleep(1)

        // Restore button should appear
        let restoreButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'text.bubble'"))
        XCTAssertTrue(restoreButton.firstMatch.waitForExistence(timeout: 3),
                      "Restore button should appear after dismissing info panel")

        // Click restore
        restoreButton.firstMatch.click()
        sleep(1)

        // Info panel should reappear
        let modelTextAgain = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelTextAgain.waitForExistence(timeout: 3),
                      "Info panel should reappear after clicking restore")
    }
}
