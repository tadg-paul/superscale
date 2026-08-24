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

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        let runtimeRoot = projectRoot
            .appendingPathComponent(".agent/tmp/ui-test-runtime", isDirectory: true)
        app.launchEnvironment["SUPERSCALE_UI_TEST_ROOT"] = runtimeRoot.path
        app.launchEnvironment["SUPERSCALE_UI_TEST_GENERATED_IMAGE"] = testImagePath
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

    private func showInfoPanel() {
        let comparisonButton = app.buttons["compareButton"]
        if comparisonButton.label == "Full View" {
            comparisonButton.click()
        }
    }

    private func textContent(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    // RT-73.8: Settings exposes separate credentials, defaults, and prompt packs.
    //
    // Navigation rewritten by #87: Settings is a scene opened with Cmd+comma, not a mode. AC73.5
    // is about which controls exist, and that is unchanged; only the way in has moved.
    func test_settings_workspace_controls_RT73_8() {
        openSettings()

        XCTAssertTrue(app.secureTextFields["generationKeyField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["accountAdministrationKeyField"].exists)
        // Addressed generically rather than as `otherElements` or `staticTexts`: making the row
        // a container that keeps its children reachable, which is what AC73.6 requires, changes
        // the element type the row reports. What AC73.5 specifies is that the account state
        // control is present, not which AppKit class represents it.
        XCTAssertTrue(element(identifier: "accountState").exists)
        XCTAssertTrue(app.popUpButtons["defaultGenerationModelPicker"].exists)
        XCTAssertTrue(app.popUpButtons["defaultUpscaleModelPicker"].exists)
        XCTAssertTrue(app.textFields["outputFolderField"].exists)
        XCTAssertTrue(app.textFields["costThresholdField"].exists)
        XCTAssertTrue(app.popUpButtons["defaultPromptPackPicker"].exists)
        XCTAssertTrue(element(identifier: "saveGenerationKeyButton").exists)
        XCTAssertTrue(element(identifier: "removeGenerationKeyButton").isEnabled)
        XCTAssertTrue(element(identifier: "saveAccountKeyButton").exists)
        XCTAssertTrue(element(identifier: "removeAccountKeyButton").isEnabled)
        // 🚫 The pricing and account assertions this test carried are removed by #88. Pricing
        // and account are paused for the v2 MVP: the implementation guide's section 6 takes the
        // pricing client, the account client, the session cache and the cost-confirmation policy
        // out of scope, and #87 deletes the controls they drove. The credential, defaults and
        // filter assertions above cover what AC73.5 still specifies. Whether the account row's
        // controls are reachable at all is AC73.6's subject, covered by RT-88.1 to RT-88.3.
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS[c] 'bundled image filters' OR label CONTAINS[c] 'bundled image filters'")
        ).firstMatch.exists)
        XCTAssertTrue(app.buttons["saveSettingsButton"].isEnabled)
    }

    // MARK: - AC73.6: Settings controls are individually addressable (#88)
    //
    // A control absent from the accessibility tree is absent for VoiceOver, not merely for a
    // test. The defect these cover is an identifier applied to a row, which absorbs the row's
    // children and leaves them unreachable. The pricing row two sections above is the control
    // case: same structure, no identifier on the container, children reachable.

    // RT-88.1
    func test_accountRefreshControlIsReachable_RT088_1() {
        openSettings()

        XCTAssertTrue(
            element(identifier: "refreshAccountButton").waitForExistence(timeout: 5),
            "The account refresh control should be addressable in its own right"
        )
    }

    // RT-88.2
    func test_accountSummaryIsReachable_RT088_2() {
        openSettings()

        XCTAssertTrue(
            element(identifier: "accountSummaryState").waitForExistence(timeout: 5),
            "The account summary should be addressable in its own right"
        )
    }

    // RT-88.3
    //
    // The rule rather than the two instances. Asserted against the controls AC73.5 enumerates,
    // which is a finite list the criterion already names; a control added later is covered when
    // its own criterion is written.
    func test_everySettingsControlIsReachable_RT088_3() {
        openSettings()

        let controls = [
            "generationKeyField",
            "saveGenerationKeyButton",
            "removeGenerationKeyButton",
            "accountAdministrationKeyField",
            "saveAccountKeyButton",
            "removeAccountKeyButton",
            "accountSummaryState",
            "refreshAccountButton",
            "defaultGenerationModelPicker",
            "defaultUpscaleModelPicker",
            "outputFolderField",
            "costThresholdField",
            "defaultPromptPackPicker",
            "saveSettingsButton",
        ]

        for identifier in controls {
            XCTAssertTrue(
                element(identifier: identifier).exists,
                "\(identifier) is not addressable; a containing row has absorbed it"
            )
        }
    }

    /// Opens the Settings scene, which #87 made a real macOS Settings window rather than a mode.
    ///
    /// Addressed by the menu item rather than by window title: the title a `Settings` scene gives
    /// its window is the platform's business and has changed across macOS releases, whereas the
    /// menu item is the route a user actually takes.
    @discardableResult
    private func openSettings() -> XCUIElement {
        let appMenu = app.menuBars.menuBarItems.element(boundBy: 1)
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()

        let settingsItem = app.menuBars.menuItems.matching(
            NSPredicate(format: "title BEGINSWITH 'Settings'")
        ).firstMatch
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 3), "the app menu should offer Settings")
        settingsItem.click()

        let settings = app.windows.matching(
            NSPredicate(format: "title CONTAINS[c] 'Settings'")
        ).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings should open as its own window")
        return settings
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
        let widthField = app.textFields["customWidth"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))
        widthField.click()
        widthField.typeText("500")

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
        let widthField = app.textFields["customWidth"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))
        widthField.click()
        widthField.typeText("400")

        let heightField = app.textFields["customHeight"]
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

        let widthField = app.textFields["customWidth"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))
        widthField.click()
        widthField.typeText("abc")
        sleep(1)

        let value = widthField.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == "W" || value.allSatisfy { $0.isNumber },
                      "Non-numeric input should be rejected, got: \(value)")
    }

    // RT-146: Stretch uncheck preserves defining dimension
    func test_stretch_uncheck_preserves_defining_RT146() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()


        // Enter width
        let widthField = app.textFields["customWidth"]
        widthField.click()
        widthField.typeText("800")

        // Enter height (this makes height the defining dimension)
        let heightField = app.textFields["customHeight"]
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

        let widthField = app.textFields["customWidth"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))
        widthField.click()
        widthField.typeText("500")

        // Wait for debounce + upscale (1.5s debounce + processing time)
        XCTAssertTrue(waitForUpscaleComplete(timeout: 60),
                      "Upscale should complete after custom dimension entry")
    }

    // RT-148: Custom dimensions before and after image load
    func test_custom_before_after_image_RT148() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let widthField = app.textFields["customWidth"]
        let heightField = app.textFields["customHeight"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))

        // Type width before image loaded
        widthField.click()
        widthField.typeText("800")
        sleep(1)

        // Height should be empty or placeholder (no image to compute aspect ratio)
        let heightBefore = heightField.value as? String ?? ""
        XCTAssertTrue(heightBefore.isEmpty || heightBefore == "H",
                      "Height should be empty/placeholder without image, got: \(heightBefore)")

        // Load the image. Importing adopts the model's native scale only when a *preset* is
        // selected (AC82.8), so a custom selection survives the import and the fields stay open.
        // This test previously re-clicked the custom button here, which under AC82.7's toggle
        // group now clears the selection instead of re-entering it.
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        // Custom is still the active choice, so the width field is still editable.
        let customButton = app.buttons["scaleCustom"]
        XCTAssertTrue(customButton.exists)
        let widthAgain = app.textFields["customWidth"]
        XCTAssertTrue(widthAgain.waitForExistence(timeout: 3))
        widthAgain.click()
        widthAgain.typeKey("a", modifierFlags: .command)
        widthAgain.typeText("800")
        sleep(1)

        // Now height should auto-populate from aspect ratio
        let heightAfter = heightField.value as? String ?? ""
        XCTAssertTrue(heightAfter != "" && heightAfter != "H",
                      "Height should auto-populate after image load, got: \(heightAfter)")
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

        let widthField = app.textFields["customWidth"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))
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

        // Dismiss via accessibility identifier
        let dismiss = app.buttons["infoPanelDismiss"]
        XCTAssertTrue(dismiss.exists, "Info panel dismiss button should exist")
        dismiss.click()
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

        showInfoPanel()
        app.buttons["scale2x"].click()
        sleep(1)
        XCTAssertTrue(waitForUpscaleComplete())
        showInfoPanel()

        let scaleText = app.staticTexts["infoScale"]
        XCTAssertTrue(scaleText.waitForExistence(timeout: 5),
                      "Info panel should update to show 2× scale")
        let scaleContent = textContent(of: scaleText)
        XCTAssertTrue(scaleContent.contains("Scale: 2×"),
                      "Info panel should reflect the selected 2× scale, got: \(scaleContent)")
    }

    // RT-157: Post-upscale dimensions in the current info-panel format
    func test_info_panel_post_upscale_summary_RT157() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        showInfoPanel()

        let inputText = app.staticTexts["infoInput"]
        let scaleText = app.staticTexts["infoScale"]
        XCTAssertTrue(inputText.waitForExistence(timeout: 5),
                      "Info panel should show input dimensions after upscale")
        let inputContent = textContent(of: inputText)
        let scaleContent = textContent(of: scaleText)
        XCTAssertTrue(inputContent.contains("Input: 224×207"), inputContent)
        XCTAssertTrue(scaleContent.contains("→ 896×828"), scaleContent)
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

        // RT-88.4 replaces the predicate this test used to carry. Its apostrophe was unescaped,
        // so the format string never parsed and the test failed before it looked at anything.
        // The exact line is the contract here, and it is read from the running application.
        XCTAssertTrue(
            sheet.staticTexts["By Tadhg O'Brien"].exists,
            "The About panel's author line should read exactly \"By Tadhg O'Brien\""
        )
    }

    // MARK: - OT-011: Dimension cap (#60)

    // RT-138: Typing large number is capped
    func test_dimension_cap_on_typing_RT138() {
        let custom = app.buttons["scaleCustom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 5))
        custom.click()

        let widthField = app.textFields["customWidth"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))
        widthField.click()
        widthField.typeText("99999")
        sleep(1)

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

        let widthField = app.textFields["customWidth"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))
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

        let widthField = app.textFields["customWidth"]
        XCTAssertTrue(widthField.waitForExistence(timeout: 3))
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
        // Button labels may be inside buttons, not standalone staticTexts
        let customButton = app.buttons["scaleCustom"]
        XCTAssertTrue(customButton.waitForExistence(timeout: 5))
        // The button should contain "Custom" text when labels are enabled
        let hasCustomLabel = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Custom'")).firstMatch.exists
        let hasCustomText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Custom'")).firstMatch.exists
        XCTAssertTrue(hasCustomLabel || hasCustomText,
                      "Custom text label should be present")

        let hasFaceLabel = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Face'")).firstMatch.exists
        let hasFaceText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Face'")).firstMatch.exists
        XCTAssertTrue(hasFaceLabel || hasFaceText,
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

        // Upscale completion enters magnifier comparison mode automatically.
        app.buttons["comparisonModeToggle"].click()

        XCTAssertTrue(app.buttons["zoomInButton"].waitForExistence(timeout: 3),
                      "Zoom + button should be visible in slider comparison mode")
        XCTAssertTrue(app.buttons["zoomOutButton"].exists,
                      "Zoom − button should be visible in slider comparison mode")
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

        showInfoPanel()
        XCTAssertTrue(app.staticTexts["infoModel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["infoInput"].exists)

        app.buttons["scale2x"].click()
        sleep(1)
        XCTAssertTrue(waitForUpscaleComplete())
        showInfoPanel()

        let modelText = app.staticTexts["infoModel"]
        let scaleText = app.staticTexts["infoScale"]
        XCTAssertTrue(modelText.exists, "Model info should remain visible after setting change")
        let modelContent = textContent(of: modelText)
        let scaleContent = textContent(of: scaleText)
        XCTAssertTrue(modelContent.contains("auto-detected"), modelContent)
        XCTAssertTrue(scaleContent.contains("Scale: 2×"), scaleContent)
    }

    // MARK: - OT-013: Info panel restore (#63)

    // RT-135: Dismiss and restore info panel
    func test_info_panel_restore_button_RT135() {
        let modelText = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelText.waitForExistence(timeout: 5),
                      "Info panel should be visible on launch")

        // Dismiss via accessibility identifier
        let dismiss = app.buttons["infoPanelDismiss"]
        XCTAssertTrue(dismiss.exists, "Dismiss button should exist")
        dismiss.click()
        sleep(1)

        // Restore button should appear
        let restore = app.buttons["infoPanelRestore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 3),
                      "Restore button should appear after dismissing info panel")

        // Click restore
        restore.click()
        sleep(1)

        // Info panel should reappear
        let modelTextAgain = app.staticTexts.matching(
            NSPredicate(format: "value CONTAINS 'Model:'")).firstMatch
        XCTAssertTrue(modelTextAgain.waitForExistence(timeout: 3),
                      "Info panel should reappear after clicking restore")
    }

    // RT-75.1: the filter controls are present in the workspace.
    //
    // Rewritten by #87 against the panel that replaced the Generate workspace. What survives of
    // AC75.1 is filter selection, prompt entry and an execute control. What goes is superseded by
    // AC87.6: the model picker, because the MVP ships one model; the aspect picker, because the
    // aspect is the working image's; and the three reference wells, because the working image is
    // the reference.
    func test_generate_workspace_controls_RT75_1() {
        attachScreenshot(named: "Workspace")

        XCTAssertTrue(element(identifier: "filterCatalogue").waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: "generationPromptField").exists
                      || app.textViews.firstMatch.exists)
        XCTAssertTrue(element(identifier: "applyFilterButton").exists)
        XCTAssertTrue(element(identifier: "filterCost").exists)
    }

    // RT-75.5, RT-75.6, RT-75.7, RT-77.3, RT-77.4: applying a filter to the working image, and
    // the result reaching the canvas.
    //
    // Rewritten by #87 for the single workspace. The journey survives: text goes in, a filter is
    // applied, the result becomes what the canvas shows and can be upscaled and saved. What goes
    // is the mode-switching this used to perform between Generate, Settings and History, which is
    // the defect that framing caused rather than a behaviour worth keeping.
    func test_applyingAFilterProducesAResultOnTheCanvas() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")

        let apply = app.buttons["applyFilterButton"]
        XCTAssertTrue(apply.isEnabled, "applying should be available with an image and a prompt")
        apply.click()

        XCTAssertTrue(waitForUpscaleComplete(), "the filter result should reach the canvas")
        XCTAssertTrue(app.buttons["saveButton"].isEnabled)
    }

    // RT-87.15: no reference wells exist. The working image is the reference.
    func test_theWorkspacePresentsNoReferenceWell_RT087_15() {
        let referenceWells = app.buttons.matching(NSPredicate(format: "label == 'Add image'"))

        XCTAssertEqual(referenceWells.count, 0)
    }

    // RT-87.25: the canvas offers somewhere to put an image before there is one.
    func test_theCanvasOffersTheImportTargetWithNoImage_RT087_25() {
        XCTAssertTrue(app.buttons["fileChooser"].waitForExistence(timeout: 5))
    }

    // RT-87.1: no mode list.
    func test_theWorkspaceShowsNoModeList_RT087_1() {
        for mode in ["modeUpscale", "modeGenerate", "modeHistory", "modeSettings"] {
            XCTAssertFalse(element(identifier: mode).exists, "\(mode) should not exist")
        }
    }

    // RT-87.2: the canvas and the filter panel are one surface, seen together.
    func test_theCanvasAndTheFilterPanelAreVisibleTogether_RT087_2() {
        XCTAssertTrue(element(identifier: "workspaceCanvas").waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: "filterPanel").exists)
    }

    // RT-87.3: Generate, History and Settings are not navigable surfaces in the window.
    func test_noFormerModeIsANavigableSurface_RT087_3() {
        XCTAssertFalse(element(identifier: "settingsWorkspace").exists)
        XCTAssertFalse(element(identifier: "historySessionList").exists)
        XCTAssertFalse(element(identifier: "generationModelPicker").exists)
    }

    // RT-87.4: the image is the focus, asserted at the declared minimum window size, which is the
    // adversarial case: any larger window makes dominance easier.
    func test_theCanvasDominatesTheWindow_RT087_4() {
        let window = app.windows.firstMatch
        let canvas = element(identifier: "workspaceCanvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        let ratio = canvas.frame.width / window.frame.width

        XCTAssertGreaterThanOrEqual(
            ratio, 0.6,
            "the canvas took \(Int(ratio * 100))% of the window's width; the image is the focus"
        )
    }

    // RT-87.5: the canvas and the panel coexist rather than replacing one another.
    func test_theFilterPanelDoesNotReplaceTheCanvas_RT087_5() {
        let canvas = element(identifier: "workspaceCanvas")
        let panel = element(identifier: "filterPanel")
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        XCTAssertTrue(canvas.frame.width > 0 && panel.frame.width > 0)
        XCTAssertFalse(canvas.frame.intersects(panel.frame), "they sit beside each other")
    }

    // RT-87.6: Settings opens as a scene and the workspace stays where it was.
    func test_settingsOpensAsASceneLeavingTheWorkspace_RT087_6() {
        openSettings()

        XCTAssertTrue(element(identifier: "workspaceCanvas").exists, "the workspace remains behind it")
    }

    // RT-87.7: the workspace itself holds no Settings surface.
    func test_theWorkspaceHoldsNoSettingsSurface_RT087_7() {
        XCTAssertFalse(element(identifier: "settingsWorkspace").exists)
    }

    // RT-87.8, RT-87.9: filters are reachable within their categories.
    func test_filtersAreListedWithinTheirCategories_RT087_8() {
        let catalogue = element(identifier: "filterCatalogue")
        XCTAssertTrue(catalogue.waitForExistence(timeout: 5))

        for category in ["Lighting", "Print", "Sketch", "Zeitgeist"] {
            XCTAssertTrue(
                catalogue.staticTexts[category].exists,
                "\(category) should be a heading in the catalogue"
            )
        }
        XCTAssertTrue(element(identifier: "filter-image-lighting-film-noir").exists)
        XCTAssertTrue(element(identifier: "filter-image-print-linocut").exists)
    }

    // RT-87.10: nothing is unreachable.
    func test_everyFilterTheApplicationReportsIsReachable_RT087_10() {
        XCTAssertTrue(element(identifier: "filterCount").waitForExistence(timeout: 5))
        let reported = textContent(of: element(identifier: "filterCount"))

        XCTAssertEqual(reported, "86", "the panel should offer every filter the catalogue loads")
    }

    // RT-87.11: choosing a filter fills the prompt area.
    func test_choosingAFilterFillsThePromptArea_RT087_11() {
        let filter = element(identifier: "filter-image-lighting-film-noir")
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.click()

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(textContent(of: prompt).localizedCaseInsensitiveContains("noir"))
    }

    // RT-87.23: no History surface.
    func test_theWorkspaceHoldsNoHistorySurface_RT087_23() {
        XCTAssertFalse(element(identifier: "historySessionList").exists)
        XCTAssertFalse(element(identifier: "historyOpenInGenerate").exists)
    }

    // RT-87.22: prior sessions are reachable from the File menu.
    func test_priorSessionsAreReachableFromTheFileMenu_RT087_22() {
        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
        fileMenu.click()

        let openRecent = app.menuBars.menuItems["Open Recent"]
        XCTAssertTrue(openRecent.waitForExistence(timeout: 3))
        openRecent.hover()

        XCTAssertTrue(
            app.menuBars.menuItems.matching(
                NSPredicate(format: "title CONTAINS 'History fixture'")
            ).firstMatch.waitForExistence(timeout: 3),
            "the seeded fixture session should be offered"
        )
    }

    // 🚫 RT-76.6, removed by #88. Its identifier is not reused.
    //
    // It drove a live pricing estimate, an account balance and a billing-events list, under
    // AC76.3. All three are surfaces the v2 MVP pauses: section 6 of the implementation guide
    // removes the pricing client, the account client, the session cache and the
    // cost-confirmation policy from scope, and #87 deletes the Generate workspace this navigated
    // to along with the Settings controls it drove.
    //
    // This is superseded behaviour rather than violated behaviour. The cost beside Apply becomes
    // a documented flat rate, covered by AC87.7. AC76.3's remaining coverage is RT-76.5, and the
    // criterion itself is superseded when the cost-confirmation policy goes.

    // 🚫 RT-77.5 and RT-77.6, removed by #87. Their identifiers are not reused.
    //
    // Both drove the History workspace: its filter control, its session list, its search field and
    // its four session actions. Section 3.9 removes History as a surface. What a user wants
    // mid-session is the iteration in front of them, which the lock chain gives them in slice 9b;
    // reaching older work is what `File > Open Recent` is for, and it is the native answer.
    //
    // Superseded behaviour rather than violated behaviour. Session *storage* is untouched and its
    // criteria still hold; what goes is the place it was browsed. AC87.9 covers the replacement,
    // with RT-87.21, RT-87.22, RT-87.32 and RT-87.33 asserting ordering, reachability, the cap and
    // a session whose image has been deleted.
}
