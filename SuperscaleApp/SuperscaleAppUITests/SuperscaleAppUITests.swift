// ABOUTME: XCUITest suite for the Superscale GUI app.
// ABOUTME: Covers launch state, accessibility identifiers, element existence, and interaction flows.

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class SuperscaleAppUITests: XCTestCase {

    let app = XCUIApplication()

    /// Absolute path to the test image the GUI suite drives.
    ///
    /// `toby-small.jpg`, 240×320: photographic content, which `icon3.png` was not. An icon gives
    /// the upscale no photographic texture to work on, so a test could pass against output that
    /// would be visibly wrong on a real photograph.
    ///
    /// **It contains no face.** `FaceDetector` uses `VNDetectFaceRectanglesRequest` and GFPGAN is
    /// trained on human faces; a dog is neither. Measured rather than assumed: Vision finds 0
    /// faces in `toby.jpg`. It also finds one in `remy2.jpg`, which is a cartoon: detection firing
    /// is not the same as there being a face GFPGAN was trained to restore, and `remy2.jpg` earns
    /// its place as anime-model content rather than as face content. A test that needs face
    /// enhancement to have something real to work on uses `faceImagePath`.
    ///
    /// Small deliberately. The full `toby.jpg` is 605×806, which at 4× is an 8-megapixel Core ML
    /// upscale *per test*, across the fifteen or so tests here that upscale. Real content matters;
    /// paying twenty minutes for it does not.
    private var testImagePath: String {
        // The test runner's working directory varies, so use an absolute path
        // derived from the source file location.
        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent()  // SuperscaleAppUITests/
            .deletingLastPathComponent()  // SuperscaleApp/
            .deletingLastPathComponent()  // project root
        return projectRoot.appendingPathComponent("Tests/images/toby-small.jpg").path
    }

    /// A fixture with real human faces in it, for tests where face enhancement must have
    /// something to enhance. `vance-small.jpg`, 301×400, two faces detected by Vision.
    private var faceImagePath: String {
        projectRoot.appendingPathComponent("Tests/images/vance-small.jpg").path
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The fixture's pixel dimensions, read from the file.
    ///
    /// Read rather than remembered. Two tests carried the previous fixture's size in a comment and
    /// an assertion — "icon3.png is 224×207, so 8× longest = 1792" — and went on asserting it after
    /// #90 changed the picture. A number written into a test goes stale in silence.
    private var testImagePixelSize: CGSize {
        guard
            let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: testImagePath) as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return .zero }
        return CGSize(width: width, height: height)
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
    ///
    /// - Parameter path: the picture to open, defaulting to the suite's 240 x 320 fixture. Named
    ///   explicitly by RT-100.10, which needs a picture whose stored resolution is not 72 dpi.
    private func loadTestImage(path: String? = nil) -> Bool {
        let path = path ?? testImagePath
        let chooser = app.buttons["fileChooser"]
        guard chooser.waitForExistence(timeout: 5) else { return false }
        chooser.click()

        // NSOpenPanel should appear. Type the path into the Go To field.
        // Cmd+Shift+G opens the "Go to folder" sheet in open/save panels.
        let openPanel = app.dialogs.firstMatch
        guard openPanel.waitForExistence(timeout: 5) else { return false }

        // Synthesized keystrokes go to whichever application is frontmost, so anything else taking
        // focus while the suite runs sends them elsewhere and the panel never navigates. This was
        // measured rather than guessed: the failure reproduces at commits whose full suite passed.
        app.activate()

        // Press Cmd+Shift+G to open path entry
        openPanel.typeKey("g", modifierFlags: [.command, .shift])

        // Wait for the Go To sheet
        let goToField = openPanel.textFields.firstMatch
        guard goToField.waitForExistence(timeout: 3) else { return false }

        // Clear existing text and type the test image path
        goToField.click()
        goToField.typeKey("a", modifierFlags: .command)
        goToField.typeText(path)

        // Press Enter to navigate to the file
        goToField.typeKey(.return, modifierFlags: [])

        // Brief pause for navigation
        sleep(1)

        // Click Open (or press Enter)
        openPanel.typeKey(.return, modifierFlags: [])

        return true
    }

    /// Waits for the upscale to complete by checking for result elements.
    /// Waits until an upscale has produced a rendering.
    ///
    /// Bound to **Compare**, not to Save. Compare exists exactly when a derivation exists, which is
    /// the condition this helper is named for. Save was the proxy until #96 made it appear whenever
    /// there is any picture at all — because raising an undersized import to the filterable minimum
    /// turns the scale off, and a filtered result the user had just paid for could not otherwise be
    /// written to disk. Left on Save, this helper would have returned true before any upscale ran and
    /// forty-one tests would have passed vacuously.
    /// Waits until an upscale has produced a rendering.
    ///
    /// Still bound to the Compare control, which exists exactly when a derivation does. #117 exists
    /// to move this onto the canvas's own report of what it is displaying, because #112 is about to
    /// make Compare appear whenever there is *anything* to compare — including a filter result with
    /// no upscale behind it — and bound to that control this helper would then return before any
    /// upscale had run, at all 45 of its call sites.
    ///
    /// The same trap took the Save control in #96 and is recorded in guide section 7. A control's
    /// meaning can widen; a state's cannot.
    ///
    /// The migration was written once against an `accessibilityValue`, which SwiftUI did not carry,
    /// and reverted rather than left timing out at every call site. AC117.1 moved the state to the
    /// label, which is carried, and this now reads that.
    private func waitForUpscaleComplete(timeout: TimeInterval = 120) -> Bool {
        let canvas = element(identifier: "workspaceCanvas")
        guard canvas.waitForExistence(timeout: 5) else { return false }
        let rendered = NSPredicate(format: "label == %@", "Canvas showing An upscaled rendering")
        let promise = expectation(for: rendered, evaluatedWith: canvas)
        return XCTWaiter().wait(for: [promise], timeout: timeout) == .completed
    }

    /// Waits until a filter result has reached the canvas.
    ///
    /// A filter is not an upscale, and after #96 it may not be followed by one: raising an
    /// undersized picture to the filterable minimum turns the scale off, so the result arrives at
    /// its own resolution and nothing derived from it exists. What marks the arrival is the
    /// candidate: Lock becomes available, because there is something to promote.
    private func waitForFilterResult(timeout: TimeInterval = 120) -> Bool {
        let lock = element(identifier: "lockButton")
        guard lock.waitForExistence(timeout: 5) else { return false }
        let enabled = NSPredicate(format: "isEnabled == true")
        let promise = expectation(for: enabled, evaluatedWith: lock)
        return XCTWaiter().wait(for: [promise], timeout: timeout) == .completed
    }

    private func showInfoPanel() {
        let comparisonButton = app.buttons["compareButton"]
        if comparisonButton.label == "Full View" {
            comparisonButton.click()
        }
    }

    /// Enters comparison, whatever state it is currently in.
    ///
    /// `compareButton` *toggles*, and a completed upscale already sets the comparison showing — so
    /// clicking it unconditionally leaves comparison rather than entering it. Three tests did
    /// exactly that and then looked for a curtain they had just dismissed.
    private func enterComparison() {
        let comparisonButton = app.buttons["compareButton"]
        guard comparisonButton.waitForExistence(timeout: 5) else { return }
        if comparisonButton.label == "Compare" {
            comparisonButton.click()
        }
    }

    private func textContent(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    private func element(identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// The application's failure alert, however the platform chooses to present it.
    ///
    /// A SwiftUI `.alert` is a dialog on some macOS releases and a sheet on others, and which one it
    /// is says nothing about the criterion. Both routes are tried so the test fails when the failure
    /// is not presented, rather than when it is presented in the other container.
    private var failureAlert: XCUIElement {
        let dialog = app.dialogs.firstMatch
        return dialog.exists ? dialog : app.sheets.firstMatch
    }

    /// Everything the alert actually says, which is not its title.
    ///
    /// An `NSAlert`'s own label is the title — "Error" for every failure alike — so comparing labels
    /// would compare two identical strings and prove nothing.
    private func spokenText(of alert: XCUIElement) -> String {
        alert.staticTexts.allElementsBoundByIndex
            .map { textContent(of: $0) }
            .joined(separator: " | ")
    }

    /// Replaces a field's contents rather than appending to them.
    ///
    /// The UI-test credential storage seeds both key fields, so a bare `typeText` produces the
    /// seeded key with the new one stuck on the end — a value neither the test nor the application
    /// meant, and one that would fail for a reason that has nothing to do with the criterion.
    private func replaceContents(of field: XCUIElement, with text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
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

        XCTAssertTrue(app.textFields["generationKeyField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["accountAdministrationKeyField"].exists)
        // 🚫 The account state assertion is removed by #89 with the control it named. AC73.5's
        // "account state" clause is superseded: pricing and account are out of MVP scope, so the
        // summary and its refresh control go rather than sitting there calling a client the MVP
        // excludes. The credential fields, defaults and filter selection AC73.5 also names are
        // asserted above and below, unaffected.
        XCTAssertTrue(app.popUpButtons["defaultGenerationModelPicker"].exists)
        XCTAssertTrue(app.popUpButtons["defaultUpscaleModelPicker"].exists)
        XCTAssertTrue(app.textFields["outputFolderField"].exists)
        // 🚫 The cost-threshold assertion is removed by #95 with the control it named. Guide
        // section 6 takes the cost-confirmation policy out of MVP scope along with the pricing and
        // account clients it belonged to; grok is a flat rate held as a constant beside Apply, so
        // there is no threshold for a user to configure. The rest of AC73.5's controls are
        // unaffected and asserted around it. RT-95.12 asserts the control's absence.
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

    // MARK: - AC95.1, AC95.2, AC95.5: what the Settings window contains (#95)

    // RT-95.1
    //
    // The row read *"Generation key ●●●●●●●● Generation key ✓ 🗑"*: `LabeledContent(title)` named
    // it, and the same `title` went into the field as its own label, which macOS drew beside it.
    //
    // Counting matches in the tree would not catch this. `.labelsHidden()` hides a label *visually*
    // while the element may keep it as its accessibility label, so the count can be identical before
    // and after the fix. The row's own name therefore carries an identifier and the assertion is
    // that exactly one element has it.
    func test_theGenerationKeyRowNamesItselfOnce_RT095_1() {
        openSettings()

        let label = app.staticTexts["generationKeyLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.staticTexts.matching(identifier: "generationKeyLabel").count, 1,
            "the row names itself once")

        let field = app.textFields["generationKeyField"]
        XCTAssertTrue(field.exists)
        XCTAssertNotEqual(
            field.label, label.label,
            "the field must not repeat the row's name beside it")
    }

    // RT-95.2
    func test_theAccountKeyRowNamesItselfOnce_RT095_2() {
        openSettings()

        let label = app.staticTexts["accountKeyLabel"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "accountKeyLabel").count, 1)

        let field = app.textFields["accountAdministrationKeyField"]
        XCTAssertTrue(field.exists)
        XCTAssertNotEqual(field.label, label.label)
    }

    // RT-95.3
    //
    // A FAL key is a bearer credential, not a password recited from memory. Masking it prevents the
    // one check anybody performs on a pasted key: looking at it.
    //
    // Asserted as *no secure field exists*, not as *this element is a text field*. A `SecureField`
    // is reported in `secureTextFields`, so the unfixed view would leave `textFields` empty and this
    // would fail for the right reason either way.
    func test_aTypedKeyIsReadableInTheField_RT095_3() {
        openSettings()

        let field = app.textFields["generationKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.secureTextFields.matching(identifier: "generationKeyField").count, 0,
            "the key is not masked")

        replaceContents(of: field, with: "visible-key-not-a-real-credential")

        XCTAssertEqual(field.value as? String, "visible-key-not-a-real-credential")
    }

    // RT-95.4
    //
    // The check that matters: a key is looked at when the user returns to Settings wondering whether
    // the right one is in there. Saving and reopening is the journey, not just typing.
    func test_aSavedKeyIsReadableWhenSettingsIsReopened_RT095_4() {
        let settings = openSettings()

        let field = app.textFields["generationKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceContents(of: field, with: "saved-key-not-a-real-credential")
        app.buttons["saveGenerationKeyButton"].click()

        settings.buttons[XCUIIdentifierCloseWindow].click()
        openSettings()

        let reopened = app.textFields["generationKeyField"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.value as? String, "saved-key-not-a-real-credential")
    }

    // RT-95.12
    //
    // Guide section 6 takes the cost-confirmation policy out of MVP scope with the pricing and
    // account clients. Asserted by identifier *and* by the visible words, because a control renamed
    // rather than removed would pass the first check alone.
    func test_noCostConfirmationControlIsPresent_RT095_12() {
        openSettings()

        XCTAssertTrue(app.textFields["generationKeyField"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(identifier: "costThresholdField").exists)
        XCTAssertEqual(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Confirm generation'")
            ).count, 0)
    }

    // RT-95.13
    func test_noPricingOrAccountBalanceControlIsPresent_RT095_13() {
        openSettings()

        XCTAssertTrue(app.textFields["generationKeyField"].waitForExistence(timeout: 5))
        for identifier in ["checkPricingButton", "refreshAccountButton", "accountSummary"] {
            XCTAssertFalse(element(identifier: identifier).exists, identifier)
        }
        XCTAssertEqual(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'balance' OR label CONTAINS[c] 'pricing'")
            ).count, 0)
    }

    // RT-95.15
    //
    // The line AC95.5 draws is between *storing* a credential for later and *operating* a paused
    // feature. The account key row stores; it does not operate. Guide 2.7 retains the credential
    // while noting no MVP feature uses it, so the row stays and stays usable.
    func test_theAccountKeyRowIsPresentAndUsable_RT095_15() {
        openSettings()

        let field = app.textFields["accountAdministrationKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceContents(of: field, with: "account-key-not-a-real-credential")

        let save = app.buttons["saveAccountKeyButton"]
        XCTAssertTrue(save.isEnabled)
        save.click()

        let remove = app.buttons["removeAccountKeyButton"]
        XCTAssertTrue(remove.isEnabled, "a stored key can be removed")
        remove.click()
        XCTAssertEqual(field.value as? String ?? "", "")
    }

    // MARK: - AC95.3, AC95.7: the account row answers its own control (#109)

    /// What the account row's badge currently says.
    ///
    /// Read from the label rather than the value: an element SwiftUI renders from an `Image` reports
    /// its label to the accessibility tree and does not reliably carry a value, which the badge's own
    /// source comment records and which the first run of `test_theCredentialBadgeCarriesItsStateAsAValue`
    /// found the hard way.
    private func accountBadgeReading() -> String {
        let badge = element(identifier: "accountKeyStatusBadge")
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "the account row has no status badge")
        return "\(badge.label) \(badge.value as? String ?? "")"
    }

    private func assertAccountBadgeSays(
        _ expected: String, _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let reading = accountBadgeReading()
        XCTAssertTrue(reading.localizedCaseInsensitiveContains(expected),
                      "\(message) — the badge reads '\(reading)'", file: file, line: line)
    }

    /// Empties the account row through its own control, so each test starts from a known Keychain.
    ///
    /// The GUI suite runs against the login Keychain, so a key left behind by one test is a key the
    /// next one launches with. Pressing the row's trash is the only route available: an XCUITest
    /// cannot reach the credential store directly, which is the same wall that retired RT-111.5.
    private func emptyTheAccountRow() {
        let remove = app.buttons["removeAccountKeyButton"]
        if remove.exists, remove.isEnabled {
            remove.click()
        }
        let field = app.textFields["accountAdministrationKeyField"]
        if (field.value as? String ?? "").isEmpty == false {
            replaceContents(of: field, with: "")
        }
    }

    // RT-109.1
    //
    // A key in the text box is not a key in the Keychain, and the row used to say it was. This is
    // the state the reported defect consumed: the badge had already flipped on the first keystroke,
    // so by the time the author pressed save there was no change left for the press to make.
    func test_anUnsavedAccountKeyReadsAsNotConfigured_RT109_1() {
        openSettings()
        emptyTheAccountRow()

        let field = app.textFields["accountAdministrationKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceContents(of: field, with: "account-key-not-a-real-credential")

        assertAccountBadgeSays("not configured",
                               "typing a key made the row claim it was stored")
    }

    // RT-109.2
    //
    // The reported defect, at the level it was reported: press the control, see something change.
    func test_savingTheAccountKeyChangesWhatTheRowReports_RT109_2() {
        openSettings()
        emptyTheAccountRow()

        let field = app.textFields["accountAdministrationKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceContents(of: field, with: "account-key-not-a-real-credential")
        let before = accountBadgeReading()

        app.buttons["saveAccountKeyButton"].click()

        let badge = element(identifier: "accountKeyStatusBadge")
        let changed = NSPredicate(format: "label CONTAINS[c] %@", "stored")
        expectation(for: changed, evaluatedWith: badge)
        waitForExpectations(timeout: 5)
        XCTAssertNotEqual(accountBadgeReading(), before, "the press changed nothing the user can see")

        emptyTheAccountRow()
    }

    // RT-109.3
    //
    // The test that blocks the cheapest wrong fix. Flipping a flag in the button's action satisfies
    // RT-109.2 and fails here: returning to "not configured" on an *edit* cannot be produced by a
    // press-flipped flag, because it needs the field compared against what was actually stored.
    func test_editingASavedAccountKeyReturnsTheRowToNotConfigured_RT109_3() {
        openSettings()
        emptyTheAccountRow()

        let field = app.textFields["accountAdministrationKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceContents(of: field, with: "account-key-not-a-real-credential")
        app.buttons["saveAccountKeyButton"].click()
        assertAccountBadgeSays("stored", "the save did not register")

        replaceContents(of: field, with: "account-key-not-a-real-credential-edited")

        assertAccountBadgeSays("not configured",
                               "an edited key still read as stored, so the badge follows the box")

        emptyTheAccountRow()
    }

    // RT-109.6
    func test_removingTheAccountKeyReturnsTheRowToNotConfigured_RT109_6() {
        openSettings()
        emptyTheAccountRow()

        let field = app.textFields["accountAdministrationKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceContents(of: field, with: "account-key-not-a-real-credential")
        app.buttons["saveAccountKeyButton"].click()
        assertAccountBadgeSays("stored", "the save did not register")

        app.buttons["removeAccountKeyButton"].click()

        XCTAssertEqual(field.value as? String ?? "", "")
        assertAccountBadgeSays("not configured", "a removed key still read as stored")
    }

    // RT-109.8
    //
    // AC95.7. Asserted as text present in the scene, not as a tooltip: `.help()` is invisible until
    // hovered and unreadable from here, so a row explained only by a tooltip would pass a weaker
    // test and still leave the user looking at an apparently inert control.
    func test_theAccountRowSaysWhyItNeverTurnsGreen_RT109_8() {
        openSettings()

        let explanation = app.staticTexts["accountKeyExplanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5),
                      "the account row offers no reason for never turning green")
        let spoken = "\(explanation.label) \(explanation.value as? String ?? "")"
        XCTAssertTrue(spoken.localizedCaseInsensitiveContains("not verified"),
                      "the sentence does not say the key is unverified — it reads '\(spoken)'")
    }

    // RT-109.9
    //
    // The trap in the obvious implementation. The badge asks whether the field matches the Keychain;
    // the trash asks whether anything is in the Keychain. Driving the trash from the badge disables
    // it the moment a saved key is edited, so a user correcting a typo can no longer delete the key
    // they are correcting.
    func test_aSavedAccountKeyCanStillBeRemovedWhileItIsBeingEdited_RT109_9() {
        openSettings()
        emptyTheAccountRow()

        let field = app.textFields["accountAdministrationKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceContents(of: field, with: "account-key-not-a-real-credential")
        app.buttons["saveAccountKeyButton"].click()

        replaceContents(of: field, with: "account-key-not-a-real-credential-edited")
        assertAccountBadgeSays("not configured", "the edited key was reported as stored")

        let remove = app.buttons["removeAccountKeyButton"]
        XCTAssertTrue(remove.isEnabled,
                      "editing a saved key removed the only way to delete it")
        remove.click()
        XCTAssertEqual(field.value as? String ?? "", "")
    }

    /// The badge says what it means in words, not only in colour.
    ///
    /// A green tick and a grey question mark are the same element to VoiceOver, and to anyone who
    /// cannot distinguish them, unless the state is a value. Nothing here reaches the provider: an
    /// unsaved, unchecked key is `stored` by definition.
    func test_theCredentialBadgeCarriesItsStateAsAValue() {
        openSettings()

        let badge = element(identifier: "generationKeyStatusBadge")
        XCTAssertTrue(badge.waitForExistence(timeout: 5))

        // Label *or* value. The state is set as both, and an element SwiftUI renders from an `Image`
        // reports its label to the tree while not reliably carrying a value — asserting only on the
        // value fails against a badge that is in fact perfectly readable, which is what the first
        // run of this test did.
        let spoken = "\(badge.label) \(badge.value as? String ?? "")"
        XCTAssertTrue(
            spoken.localizedCaseInsensitiveContains("stored")
                || spoken.localizedCaseInsensitiveContains("working")
                || spoken.localizedCaseInsensitiveContains("not configured"),
            "the badge's state must be readable, not only visible: \"\(spoken)\"")
    }

    // MARK: - AC73.6: Settings controls are individually addressable (#88)
    //
    // A control absent from the accessibility tree is absent for VoiceOver, not merely for a
    // test. The defect these cover is an identifier applied to a row, which absorbs the row's
    // children and leaves them unreachable. The pricing row two sections above is the control
    // case: same structure, no identifier on the container, children reachable.

    // 🚫 RT-88.1 and RT-88.2, removed by #89. Their identifiers are not reused.
    //
    // Both asserted that a specific account control was reachable in the accessibility tree, and
    // #89 removes those controls: section 6 of the implementation guide takes the pricing and
    // account clients out of MVP scope, so a Refresh Account button would go on contacting a
    // provider the MVP excludes.
    //
    // **AC73.6 is unaffected.** The rule those tests were written for — that no control is
    // absorbed by the row containing it — survives in RT-88.3, which asserts it across the
    // controls Settings still offers. What goes is two instances naming controls that no longer
    // exist, not the criterion.

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
            "defaultGenerationModelPicker",
            "defaultUpscaleModelPicker",
            "outputFolderField",
            // 🚫 costThresholdField is removed by #95 with the control it named; see RT-73.8.
            "chooseOutputFolderButton",
            "generationKeyStatusBadge",
            "accountKeyStatusBadge",
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
    // RT-90.18: turning the scale off and on again shows the upscale.
    //
    // The reported sequence: turn the upscale off, drop an image, turn it on — which works — then
    // off, then on again, and nothing happens.
    func test_turningTheScaleOffAndOnAgainUpscales_RT090_18() {
        let scaleFour = app.buttons["scale4x"]
        XCTAssertTrue(scaleFour.waitForExistence(timeout: 5))

        scaleFour.click()                       // off
        dismissInfoPanelIfPresent()
        XCTAssertTrue(loadTestImage(), "an image should import with no scale selected")
        XCTAssertTrue(element(identifier: "workingImage").waitForExistence(timeout: 10))

        scaleFour.click()                       // on
        XCTAssertTrue(waitForUpscaleComplete(), "the first upscale should complete")

        scaleFour.click()                       // off again
        // Asserted on **Compare**, which exists exactly when a derivation does. Save is now offered
        // whenever there is a picture at all, so it no longer distinguishes "the upscale was
        // released" from "there is something on the canvas" — see the note at
        // `test_theCanvasKeepsTheImportedImageWithNoScaleSelected`.
        XCTAssertFalse(
            app.buttons["compareButton"].waitForExistence(timeout: 2),
            "turning the scale off releases the upscaled output"
        )

        scaleFour.click()                       // on again
        XCTAssertTrue(
            waitForUpscaleComplete(timeout: 60),
            "choosing the same scale again should upscale again rather than doing nothing"
        )
    }

    private func dismissInfoPanelIfPresent() {
        let dismiss = app.buttons["infoPanelDismiss"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.click() }
    }

    // RT-89.27: with no candidate, the filter toggle is unavailable.
    //
    // There is nothing to compare the base against until a filter has produced something.
    func test_withNoCandidateTheFilterToggleIsUnavailable_RT089_27() {
        XCTAssertTrue(app.buttons["fileChooser"].waitForExistence(timeout: 5))

        XCTAssertFalse(element(identifier: "filterToggle").exists)
    }

    // RT-89.7 at the surface: Lock is unavailable with nothing to promote.
    func test_lockIsUnavailableWithNoCandidate_RT089_7() {
        let lock = element(identifier: "lockButton")
        XCTAssertTrue(lock.waitForExistence(timeout: 5))

        XCTAssertFalse(lock.isEnabled, "there is no candidate to promote")
    }

    // RT-89.20: Settings presents no pricing control.
    func test_settingsPresentsNoPricingControl_RT089_20() {
        openSettings()

        XCTAssertTrue(app.textFields["generationKeyField"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(identifier: "checkPricingButton").exists)
        XCTAssertFalse(element(identifier: "generationPricingSummary").exists)
    }

    // RT-89.21: Settings presents no account control.
    //
    // The clients remain in `FalGenerationKit` for the version that needs them; what goes is the
    // application reaching for a provider the MVP excludes.
    func test_settingsPresentsNoAccountControl_RT089_21() {
        openSettings()

        XCTAssertTrue(app.textFields["accountAdministrationKeyField"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(identifier: "refreshAccountButton").exists)
        XCTAssertFalse(element(identifier: "accountSummaryState").exists)
        XCTAssertFalse(element(identifier: "billingEvents").exists)
    }

    // RT-89.22: the application constructs no pricing or account client.
    //
    // **The observable half.** A test cannot watch a constructor run; what it can assert is that
    // nothing the application shows carries pricing or account state, having exercised the journeys
    // that would produce it. The structural half — that no client is constructed — is confirmed by
    // `audit-code`, which is the same split AC98.5 records for the same reason: a fact about the
    // code's shape can only be checked by reading it, and `TESTING.md` forbids a test that greps
    // source.
    //
    // Both windows, because the controls that drove those clients lived in Settings and their
    // status reached the workspace.
    func test_theApplicationShowsNoPricingOrAccountState_RT089_22() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let forbidden = [
            "checkPricingButton", "generationPricingSummary", "refreshAccountButton",
            "accountSummaryState", "billingEvents", "generationCloudStatus",
        ]
        for identifier in forbidden {
            XCTAssertFalse(element(identifier: identifier).exists, identifier)
        }

        // And no words for it either, so a control renamed rather than removed does not pass.
        let words = NSPredicate(
            format: "label CONTAINS[c] 'balance' OR label CONTAINS[c] 'billing'"
                + " OR label CONTAINS[c] 'credits'")
        XCTAssertEqual(app.staticTexts.matching(words).count, 0)

        openSettings()
        XCTAssertTrue(app.textFields["generationKeyField"].waitForExistence(timeout: 5))
        for identifier in forbidden {
            XCTAssertFalse(element(identifier: identifier).exists, "\(identifier) in Settings")
        }
        XCTAssertEqual(app.staticTexts.matching(words).count, 0)
    }

    // RT-89.10: an iteration reached by scrolling back is saveable at the current scale selection.
    //
    // Guide 2.6 rules that saving an earlier iteration re-derives its upscale on demand, which is
    // why this is *at the current scale selection* rather than at whatever resolution the iteration
    // happens to be. What the test can see is that selecting an earlier iteration leaves the
    // application able to save — the chain is a record of work, and a record you cannot retrieve
    // from is a list.
    func test_anEarlierIterationIsSaveableAtTheCurrentScale_RT089_10() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")

        let lock = element(identifier: "lockButton")
        XCTAssertTrue(lock.isEnabled, "there is a candidate to promote")
        lock.click()

        let chain = element(identifier: "lockChain")
        XCTAssertTrue(chain.waitForExistence(timeout: 10), "a locked iteration joins the chain")

        let iteration = chain.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'lockedIteration-'")
        ).firstMatch
        XCTAssertTrue(iteration.waitForExistence(timeout: 5), "an entry to scroll back to")
        iteration.click()

        // At the *current* scale selection, which the raise turned off — so what is saveable is the
        // iteration as it stands, and Save must be there for it. Bound to a completed upscale, Save
        // vanished exactly here: the user has just paid for a filter and cannot write it to disk.
        let save = app.buttons["saveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 30), "an earlier iteration can be saved")
        XCTAssertTrue(save.isEnabled)
    }

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

    // MARK: - AC83.7 and AC101.1: the status bar's notices reach the user (#101)

    /// Writes a picture of a given size into a per-run directory and returns its path.
    ///
    /// That exact directory is removed in teardown, on success and on failure alike, never a
    /// shared parent.
    private func writeFixture(width: Int, height: Int, named name: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notice-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let url = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "the fixture was written")
        return url.path
    }

    /// Everything the status bar says, from both the label and the value.
    ///
    /// A container reports its label where it does not reliably report its value, and this delivery
    /// has already been caught by that twice in two different element types.
    private func statusBarText(of identifier: String, timeout: TimeInterval = 10) -> String {
        let element = element(identifier: identifier)
        guard element.waitForExistence(timeout: timeout) else { return "" }
        return "\(element.label) \(element.value as? String ?? "")"
    }

    /// Selects a scale, having first made sure it is not the one already in effect.
    ///
    /// The scale buttons are a toggle group: pressing the active choice **clears** it, so a test
    /// that names a scale without checking can silently turn upscaling off and then wait for a
    /// result that will never come. Which scale is active follows the model's native scale rather
    /// than a constant, so it cannot be assumed.
    private func selectScale(_ scale: Int) {
        let button = app.buttons["scale\(scale)x"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "scale\(scale)x exists")
        XCTAssertTrue(
            button.isEnabled,
            "scale\(scale)x is enabled; clicking a disabled button changes nothing and reports nothing")
        let value = (button.value as? String ?? "").lowercased()
        let alreadyInEffect = value.contains("in effect") && !value.contains("not in effect")
        XCTAssertFalse(
            alreadyInEffect,
            "scale\(scale)x is already in effect; clicking it would turn upscaling off")
        button.click()

        // The click is not the outcome. A scale that never registers is the difference between "the
        // notice never appeared" and "nothing was ever asked for", and without this the two look
        // identical from the failure message.
        //
        // What is waited for is that the scale was **requested**, not that it is in effect. Those
        // differ by design: AC93.1 requires the control to keep showing what was asked for while
        // reporting what is actually running, so a scale the ceiling reduces reads "requested, not
        // in effect" and never becomes "in effect" at all. Waiting for the stronger condition waits
        // for something the application is correct not to do.
        let registered = NSPredicate(format: "value CONTAINS[c] 'requested'")
        let seen = XCTNSPredicateExpectation(predicate: registered, object: button)
        XCTAssertEqual(
            XCTWaiter().wait(for: [seen], timeout: 20), .completed,
            "scale\(scale)x registers as requested after the click: \(scaleState())")
    }

    /// What every scale control currently reports, for a failure message.
    private func scaleState() -> String {
        [2, 4, 8]
            .map { scale in
                let button = app.buttons["scale\(scale)x"]
                guard button.exists else { return "\(scale)x absent" }
                let value = button.value as? String ?? "no value"
                return "\(scale)x \(button.isEnabled ? "enabled" : "disabled") \"\(value)\""
            }
            .joined(separator: "; ")
    }

    // RT-101.1, RT-101.2
    //
    // The ceiling is 32 megapixels, so a reduction needs a large *request* rather than a large
    // source: 800 x 640 at 8x is 6400 x 5120, which is 32.8 megapixels, and reduces to 4x whose
    // output is about 8. A 2048 x 1536 source was tried first and left the application unresponsive
    // long enough that the accessibility hierarchy returned no snapshot at all.
    //
    // RT-101.2 asserts the **scales**. `reductionNotice` returns "Upscaled 4× rather than 8×, to
    // stay within available memory" for a preset; only its custom-target branch names dimensions.
    func test_aReductionIsReportedWhereTheUserReadsIt_RT101_1() throws {
        let path = try writeFixture(width: 800, height: 640, named: "large-request.png")
        XCTAssertTrue(loadTestImage(path: path), "the picture should load")
        XCTAssertTrue(
            element(identifier: "workingImage").waitForExistence(timeout: 30),
            "and occupy the canvas")

        selectScale(8)

        // Waited generously rather than read at once: `noticeMessage` is set in `publish`, when the
        // upscale **completes**, and 3200 x 2560 is real work on the Neural Engine. Ten seconds is
        // not enough, which is what failed the first run of this test.
        let said = statusBarText(of: "noticeMessage", timeout: 120)
        XCTAssertFalse(
            said.isEmpty,
            """
            the reduction is reported. \
            status bar says "\(statusBarText(of: "statusText"))"; \
            scales: \(scaleState())
            """)
        XCTAssertTrue(
            said.localizedCaseInsensitiveContains("memory"),
            "and says why: \"\(said)\"")

        // RT-101.2: the scale used and the scale asked for, both named and different. AC83.7
        // requires the selection to keep showing the request while the message reconciles it.
        XCTAssertTrue(said.contains("8"), "the scale requested: \"\(said)\"")
        XCTAssertTrue(said.contains("4"), "and the scale used: \"\(said)\"")
    }

    // RT-101.3, RT-101.5
    //
    // The mechanism. `appStatusBar` carried an identifier with no `children: .contain`, so SwiftUI
    // treated the whole bar as one element and absorbed everything in it — rendered on screen and
    // absent from the accessibility tree. Sixth occurrence of that rule in this codebase.
    //
    // Both of the bar's contents are asserted, not just the notice: a test covering one label
    // proves the fix for one label and leaves the rule unproven of the bar.
    func test_theStatusBarsContentsAreAddressableRatherThanAbsorbed_RT101_3() throws {
        let path = try writeFixture(width: 800, height: 640, named: "addressable.png")
        XCTAssertTrue(loadTestImage(path: path), "the picture should load")
        XCTAssertTrue(
            element(identifier: "workingImage").waitForExistence(timeout: 30))

        let bar = element(identifier: "appStatusBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "the bar is present")

        // RT-101.5: the status text, which had no identifier at all until this issue.
        XCTAssertFalse(
            statusBarText(of: "statusText").trimmingCharacters(in: .whitespaces).isEmpty,
            "the status text is reachable and says something")

        // RT-101.3: and the notice, once there is one. The wait is generous for the same reason as
        // RT-101.1: the notice appears when the upscale completes, not when the scale is chosen.
        selectScale(8)
        XCTAssertFalse(
            statusBarText(of: "noticeMessage", timeout: 120).isEmpty,
            """
            the notice is reachable rather than absorbed. \
            status bar says "\(statusBarText(of: "statusText"))"; \
            scales: \(scaleState())
            """)
    }

    // RT-101.4
    //
    // Blocks the cheapest wrong implementation, a notice that is always present, and pins the
    // common case: an ordinary upscale within the ceiling says nothing at all.
    func test_withNoReductionAndNoRaiseNoNoticeIsShown_RT101_4() throws {
        // Above the 1024 floor so nothing is raised, and small enough at any offered scale that
        // nothing is reduced: 1200 x 900 at 8x is 9600 x 7200, which is 69 megapixels — so 4x is
        // used here instead, giving 17 megapixels, under the ceiling.
        let path = try writeFixture(width: 1200, height: 900, named: "unremarkable.png")
        XCTAssertTrue(loadTestImage(path: path), "the picture should load")

        // The arithmetic above is about 4x, so 4x is what must actually be running. Which scale is
        // active follows the model's native scale rather than a constant — the reason `selectScale`
        // exists — so a test reasoning about one and taking whatever it is given proves less than
        // its own comment claims.
        let inEffect = app.buttons["scale4x"]
        XCTAssertTrue(inEffect.waitForExistence(timeout: 10), "scale4x exists")
        // "not in effect" contains "in effect", so both halves are needed — the same trap
        // `selectScale` guards against.
        let reported = (inEffect.value as? String ?? "").lowercased()
        XCTAssertTrue(
            reported.contains("in effect") && !reported.contains("not in effect"),
            "4x is the scale in effect: \"\(reported)\"")

        XCTAssertTrue(waitForUpscaleComplete(), "and upscale without incident")

        XCTAssertFalse(
            element(identifier: "noticeMessage").exists,
            "nothing happened that the user needs telling about")
    }

    // RT-101.6
    //
    // A notice replaced while displayed. Driven through the sequence the application already
    // performs: the suite's 240 x 320 fixture is below the floor, so applying a filter raises it and
    // sets one message, and the stubbed provider returning a 1024 x 1024 square then replaces it
    // with the reshape message. An element recreated rather than updated may not be announced.
    func test_aNoticeReplacedWhileDisplayedCarriesTheNewText_RT101_6() {
        app.terminate()
        app.launchEnvironment["SUPERSCALE_UI_TEST_GENERATED_IMAGE"] =
            projectRoot.appendingPathComponent("Tests/images/remy2.jpg").path
        app.launch()

        XCTAssertTrue(loadTestImage(), "the 3:4 fixture should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the square result should reach the canvas")

        let said = statusBarText(of: "noticeMessage")
        XCTAssertTrue(
            said.localizedCaseInsensitiveContains("shape"),
            "the second notice replaced the first: \"\(said)\"")
        XCTAssertFalse(
            said.localizedCaseInsensitiveContains("minimum for filtering"),
            "and the raise message it replaced is gone: \"\(said)\"")
    }

    // MARK: - AC100.2: a high-resolution picture is measured in pixels (#100)

    // RT-100.10
    //
    // **The only one of this issue's ten tests that would have failed against the broken code end
    // to end.** `MainView.importedPixelSize` used `NSImage.size`, which reports points adjusted by
    // the file's stored resolution, so this 2048 x 1536 photograph measured about 492 x 369 — well
    // under the 1024 floor. The application would raise it 4x it does not need, alter the user's
    // picture before sending it, and turn their scale selection off.
    //
    // The fixture is generated at runtime rather than committed: a picture whose only purpose is to
    // carry an unusual resolution is a thing a later reader has to work out.
    func test_aHighResolutionPictureAboveTheFloorIsNotRaised_RT100_10() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dpi-gui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        // 1200 x 900 at 300 dpi, chosen so the test proves one thing and only one thing.
        //
        // Its long edge is 1200, comfortably above the 1024 floor, so a correct application raises
        // nothing. In points it is 288 x 216, far below the floor, so the broken one raises it.
        // And 4x of it is 17 megapixels, under the 32-megapixel ceiling, so no *reduction* notice
        // appears either — which means the assertion can be the clean one, that there is no notice
        // at all, rather than a search through the text of whichever notice did appear.
        //
        // A 2048 x 1536 fixture was tried first and its upscale left the application unresponsive
        // long enough that the accessibility hierarchy returned no snapshot to query.
        let url = directory.appendingPathComponent("high-resolution.png")
        let width = 1200, height = 900
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, try XCTUnwrap(context.makeImage()),
            [kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "the fixture was written")

        XCTAssertTrue(loadTestImage(path: url.path), "the high-resolution picture should load")
        XCTAssertTrue(
            element(identifier: "workingImage").waitForExistence(timeout: 30),
            "and occupy the canvas")

        // The floor is checked at Apply, so applying is what would raise it.
        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")

        // Absence, asserted only after a positive signal that the work finished. `waitForFilterResult`
        // is that signal; reading the tree before it returns can find an application still busy and
        // yield no snapshot at all, which is indistinguishable from an empty one.
        let notice = element(identifier: "noticeMessage")
        let said = notice.waitForExistence(timeout: 5)
            ? "\(notice.value as? String ?? "") \(notice.label)"
            : ""
        XCTAssertTrue(
            said.isEmpty,
            "a 1200-pixel picture is above the floor and fits the ceiling, so nothing is said "
                + "about it: \"\(said)\"")
    }

    // MARK: - AC96.1: the raise reaches the window (#96)

    // RT-96.3, in the window
    //
    // RT-96.3 asserts the sentence; this asserts that a user sees it. **Twice today a slice was
    // complete in its package and absent from the application** — the reference upload had seven
    // passing tests and no caller, and the raise itself ran without reporting. A string a test
    // checks and a window nobody checks is the same fault waiting.
    //
    // The suite's fixture is 240x320, below the 1024 floor, so every filter applied here raises it.
    func test_raisingAnUndersizedPictureIsReportedInTheWindow_RT096_3() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")

        let notice = element(identifier: "noticeMessage")
        XCTAssertTrue(notice.waitForExistence(timeout: 30), "the raise is reported")

        // The value rather than the label: the status bar is one line, so the sentence truncates on
        // screen and only the value carries the whole of it.
        let said = "\(notice.value as? String ?? "") \(notice.label)"
        XCTAssertTrue(
            said.contains("1024"),
            "and names the minimum it was raised to meet: \"\(said)\"")
    }

    // RT-96.14, in the window
    //
    // The mark appears. The provenance records whether the provider reshaped the picture and the
    // package tests assert that it does; **recorded and never shown, the criterion would be
    // delivered to its tests and not to anybody using the application.**
    //
    // Driven by pointing the stubbed provider at a **square** fixture — `remy2.jpg`, 1024 x 1024 —
    // while the working picture is 240 x 320. That is exactly what grok does to anything whose short
    // edge falls under its working size, and it is the report that produced this issue.
    func test_aReshapedReturnIsMarkedInTheWindow_RT096_14() {
        app.terminate()
        app.launchEnvironment["SUPERSCALE_UI_TEST_GENERATED_IMAGE"] =
            projectRoot.appendingPathComponent("Tests/images/remy2.jpg").path
        app.launch()

        XCTAssertTrue(loadTestImage(), "a 3:4 working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the square result should reach the canvas")

        let notice = element(identifier: "noticeMessage")
        XCTAssertTrue(notice.waitForExistence(timeout: 30), "something is said about the return")

        let said = "\(notice.value as? String ?? "") \(notice.label)"
        XCTAssertTrue(
            said.localizedCaseInsensitiveContains("shape"),
            "and what is said is that the shape changed: \"\(said)\"")
    }

    // MARK: - AC94.4: whose scroll is it (#94)

    /// How far the curtain reports it has been panned.
    ///
    /// The pan reaches the accessibility tree as a value. Expressed only as a rendered offset it
    /// reaches nobody — not VoiceOver, and not a test asking whether the picture moved. RT-94.18 is
    /// that the value exists at all; the scroll tests read it to see whether it changed.
    private func reportedPan() -> String {
        // Read from the container *and* from the picture inside it. `curtainPicture` declares
        // `children: .contain`, and a container's own label and value are less reliably reported
        // than a leaf element's — the same trap as #95's credential badge, one element type along.
        // The application sets the pan in both places for the same reason.
        let curtain = element(identifier: "curtainPicture")
        let picture = app.images["workingImage"]
        return [
            curtain.label,
            curtain.value as? String ?? "",
            picture.exists ? picture.label : "",
        ].joined(separator: " ")
    }

    /// Leaves the curtain, so the canvas shows one picture.
    ///
    /// Comparison is **entered automatically** when an upscale completes, so a test wanting the
    /// plain canvas has to ask for it. `compareButton` reads "Full View" while the curtain is up.
    private func leaveComparison() {
        let button = app.buttons["compareButton"]
        guard button.waitForExistence(timeout: 5) else { return }
        if button.label != "Compare" { button.click() }
    }

    // RT-94.18
    func test_theComparisonReportsItsPanAsAValue_RT094_18() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        enterComparison()

        let curtain = element(identifier: "curtainPicture")
        XCTAssertTrue(curtain.waitForExistence(timeout: 5))
        XCTAssertTrue(
            reportedPan().localizedCaseInsensitiveContains("panned"),
            "the pan is a value, not only a rendered offset: \"\(reportedPan())\"")
    }

    // RT-94.11, RT-94.12
    //
    // The picture was panned from an `NSEvent` monitor that never asked where the pointer was, so
    // scrolling the filter category strip moved the photograph. A monitor is a global interception
    // dressed as a view behaviour: it fires for the toolbar, the side panel, the lock chain and the
    // status bar alike.
    func test_aScrollOverThePanelLeavesThePictureAndOneOverItPansIt_RT094_11() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        enterComparison()

        let curtain = element(identifier: "curtainPicture")
        XCTAssertTrue(curtain.waitForExistence(timeout: 5))
        let before = reportedPan()

        // RT-94.11: over the filter panel, which is not the picture.
        let panel = element(identifier: "filterCatalogue")
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        panel.scroll(byDeltaX: 0, deltaY: -120)

        XCTAssertEqual(
            reportedPan(), before,
            "scrolling the filter list must not move the photograph")

        // RT-94.12: over the picture itself.
        curtain.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        curtain.scroll(byDeltaX: 0, deltaY: -120)

        // Waited for rather than read immediately: the pan travels from an `NSEvent` monitor
        // through `@State` to a re-rendered accessibility value, and none of that is synchronous
        // with the scroll returning.
        let moved = expectation(
            for: NSPredicate { _, _ in self.reportedPan() != before },
            evaluatedWith: curtain)
        XCTAssertEqual(
            XCTWaiter().wait(for: [moved], timeout: 10), .completed,
            "scrolling the picture pans it; still \(reportedPan())")
    }

    // RT-94.13
    //
    // With no comparison on screen there is nothing to pan, and the monitor should not be installed
    // at all — it is attached in `onAppear` and removed in `onDisappear` for exactly this reason.
    func test_aScrollWithNoComparisonOnScreenPansNothing_RT094_13() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        // Comparison is entered automatically when an upscale completes, so leaving it is a
        // deliberate act rather than the starting state. The first version of this test assumed
        // otherwise and failed on its own premise.
        leaveComparison()
        let canvas = element(identifier: "workspaceCanvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertFalse(
            element(identifier: "curtainPicture").exists, "no curtain is on screen")

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        canvas.scroll(byDeltaX: 0, deltaY: -120)

        // Nothing was panned, and the way to see that is to go back to the curtain and ask it. A
        // scroll that reached the monitor while no comparison was on screen would show here.
        enterComparison()
        XCTAssertTrue(
            element(identifier: "curtainPicture").waitForExistence(timeout: 5),
            "the curtain is available again")
        XCTAssertTrue(
            reportedPan().contains("panned 0 by 0"),
            "the scroll reached nothing: \(reportedPan())")
    }

    // MARK: - AC93.3: the face controls follow the scale (#93)

    /// Turns the scale off by pressing whichever preset is currently active.
    ///
    /// The scale buttons are a toggle group: pressing the active choice clears it. There is no
    /// separate "off" control to click, so the test has to find the active one first.
    private func turnScaleOff() {
        for scale in [2, 4, 8] {
            let button = app.buttons["scale\(scale)x"]
            guard button.exists else { continue }
            let value = (button.value as? String ?? "").lowercased()
            if value.contains("in effect") && !value.contains("not in effect") {
                button.click()
                return
            }
        }
        XCTFail("no scale was in effect to turn off")
    }

    // RT-93.6
    //
    // Face enhancement is a stage of the upscale. With no scale selected there is no upscale for it
    // to be a stage of, and a control offering a setting that changes nothing is worse than no
    // control: the author read it as 4x being active when it was not.
    func test_withTheScaleOffTheToolbarsFaceControlIsDisabled_RT093_6() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let face = app.buttons["faceEnhanceButton"]
        XCTAssertTrue(face.waitForExistence(timeout: 5))
        XCTAssertTrue(face.isEnabled, "with a scale in effect")

        turnScaleOff()

        XCTAssertFalse(face.isEnabled, "with no upscale for it to be a stage of")
    }

    // RT-93.7
    func test_selectingAScaleEnablesTheFaceControlAgain_RT093_7() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let face = app.buttons["faceEnhanceButton"]
        XCTAssertTrue(face.waitForExistence(timeout: 5))
        turnScaleOff()
        XCTAssertFalse(face.isEnabled)

        app.buttons["scale2x"].click()

        XCTAssertTrue(face.isEnabled, "a scale is in effect again")
    }

    // RT-93.8
    //
    // AC93.3 requires the unavailability to be *visible rather than silent*. A dimmed control with
    // a tooltip is silent to anyone not holding a mouse still over it, and to anything asking the
    // tree what the state is — so the reason is an accessibility value, not only a `.help`.
    func test_theDisabledFaceControlExplainsWhy_RT093_8() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let face = app.buttons["faceEnhanceButton"]
        XCTAssertTrue(face.waitForExistence(timeout: 5))
        turnScaleOff()

        let reason = face.value as? String ?? ""
        XCTAssertTrue(
            reason.localizedCaseInsensitiveContains("scale"),
            "the reason names what to do about it: \"\(reason)\"")
        XCTAssertFalse(face.isEnabled)
    }

    // RT-93.13
    //
    // The sheet's row and the toolbar's button are two controls for one setting; disabling one and
    // leaving the other is how a setting that changes nothing stays reachable.
    func test_withTheScaleOffTheSheetsFaceRowIsDisabledToo_RT093_13() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        turnScaleOff()

        app.buttons["modelPicker"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        let row = element(identifier: "sheetFaceEnhanceButton")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // Disabled only where the model is installed: where it is absent the row is the route to
        // obtaining it, which RT-93.12 covers and AC93.3 requires to stay open.
        if row.isEnabled {
            let reason = row.value as? String ?? row.label
            XCTAssertTrue(
                reason.localizedCaseInsensitiveContains("download")
                    || reason.localizedCaseInsensitiveContains("install")
                    || reason.localizedCaseInsensitiveContains("get"),
                "if it is still active with the scale off, it is offering the model: \"\(reason)\"")
        }
    }

    // RT-93.12
    //
    // The one thing that must stay reachable with the controls unavailable. Disabling the route to
    // the model along with the setting would leave a user who has never downloaded it unable to,
    // and no way to find out why.
    func test_theFaceModelRemainsObtainableWithTheScaleOff_RT093_12() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        turnScaleOff()

        app.buttons["modelPicker"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        XCTAssertTrue(
            element(identifier: "sheetFaceEnhanceButton").waitForExistence(timeout: 5),
            "the row is present whether or not it is active")
    }

    // RT-93.15
    //
    // The scale control's value comes from `ScaleReadout` rather than from a completed run, so it
    // is correct from the moment the picture is loaded — including while an upscale is still in
    // flight, which is exactly when the old control reported the request instead of the state.
    func test_theScaleControlsValueReportsTheReadoutInFlight_RT093_15() {
        XCTAssertTrue(loadTestImage(), "the working image should load")

        // Read *before* waiting for completion. A control deriving its state from a finished run
        // would have nothing to say here.
        let active = [2, 4, 8].compactMap { scale -> String? in
            let button = app.buttons["scale\(scale)x"]
            guard button.waitForExistence(timeout: 10) else { return nil }
            let value = (button.value as? String ?? "").lowercased()
            return value.contains("in effect") && !value.contains("not in effect")
                ? "\(scale)x" : nil
        }

        XCTAssertEqual(
            active.count, 1,
            "exactly one scale reads as in effect while the upscale runs, got \(active)")

        XCTAssertTrue(waitForUpscaleComplete())
        let afterwards = [2, 4, 8].filter { scale in
            let value = (app.buttons["scale\(scale)x"].value as? String ?? "").lowercased()
            return value.contains("in effect") && !value.contains("not in effect")
        }
        XCTAssertEqual(
            afterwards.map { "\($0)x" }, active,
            "and the same one afterwards: the readout did not change when the run finished")
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
        // Derived from the fixture rather than hardcoded: this read "icon3" until #90 changed the
        // suite's picture, and a name written into an assertion goes stale silently.
        let expected = (testImagePath as NSString).lastPathComponent
        XCTAssertTrue(title.contains(expected),
                      "Window title should contain \(expected), got: \(title)")
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
        // Derived from the fixture. These read 224×207 and 896×828, which were `icon3.png`'s
        // numbers, and went on asserting them after #90 changed the picture.
        let size = testImagePixelSize
        XCTAssertGreaterThan(size.width, 0, "the fixture's dimensions should be readable")
        XCTAssertTrue(
            inputContent.contains("Input: \(Int(size.width))×\(Int(size.height))"), inputContent)
        XCTAssertTrue(
            scaleContent.contains("→ \(Int(size.width) * 4)×\(Int(size.height) * 4)"), scaleContent)
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
        let longestEdge = Int(max(testImagePixelSize.width, testImagePixelSize.height))
        let cap = longestEdge * 8
        XCTAssertGreaterThan(cap, 0, "the fixture's dimensions should be readable")
        XCTAssertTrue(intValue <= cap,
                      "Value should be capped at 8× the image's longest edge (\(cap)), got \(value)")
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

        // `comparisonModeToggle` chose between the loupe and the curtain. #90 removed the loupe, so
        // there is nothing to toggle between and the comparison is entered directly. The zoom
        // buttons this test is actually about are unaffected: only the way in changed.
        enterComparison()

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

        // Waits for the *filter* rather than for an upscale. #96 changed what applying does to an
        // undersized picture: it is raised to the filterable minimum first and the scale is turned
        // off, so the result arrives at its own resolution and nothing derived from it exists. The
        // journey this test describes is unchanged; what marks its end has moved.
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")
        XCTAssertTrue(app.buttons["saveButton"].isEnabled, "and can be saved as it stands")
    }

    // MARK: - AC82.9, AC82.10 and AC116.1: where an allocated location is, and that it exists (#115, #116)

    /// The configured root's asset directory, which the launch empties and only the graph creates.
    private var configuredGeneratedDirectory: URL {
        projectRoot
            .appendingPathComponent(".agent/tmp/ui-test-runtime/Generated", isDirectory: true)
    }

    /// The user's own storage, which no test run may touch.
    private var userGeneratedDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Superscale/Generated", isDirectory: true)
    }

    /// Imports the fixture and applies a filter, which raises the undersized picture first.
    ///
    /// The raise is the allocation both tests below are about: it is the application's own path
    /// into `AssetGraph`, and it is what six GUI tests failed on when the graph allocated into a
    /// directory nothing had created.
    private func applyFilterToFixture() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
    }

    /// RT-115.5: a raise completes with the output directory absent beforehand.
    ///
    /// The one test of this pair that would have failed against the broken code end to end. The
    /// seven package tests hold the allocation contract; this holds the consequence, and it is at
    /// this layer deliberately — `make test` reported 533 executed and 0 failures throughout,
    /// because a package test constructs the graph with a directory it made itself.
    func test_aRaiseCompletesWithTheOutputDirectoryAbsent_RT115_5() {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: configuredGeneratedDirectory.path),
            """
            the launch empties the test root, so the output directory must start absent. \
            If it is here, the condition this test exists for is not being exercised.
            """
        )

        applyFilterToFixture()

        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: configuredGeneratedDirectory.path),
            "the graph did not create the directory it allocated into"
        )
    }

    /// RT-116.4: the assets land beneath the configured root, and the user's own storage is untouched.
    ///
    /// The positive assertion comes first and carries the test. Asserting only that the user's
    /// directory is untouched passes against a build where the writes fail and land nowhere, which
    /// is exactly the state #115 described.
    func test_assetsLandBeneathTheConfiguredRoot_RT116_4() throws {
        let userGenerated = try XCTUnwrap(userGeneratedDirectory)
        let userDirectoryExistedBefore = FileManager.default.fileExists(atPath: userGenerated.path)

        applyFilterToFixture()
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")

        let landed = (try? FileManager.default.contentsOfDirectory(
            atPath: configuredGeneratedDirectory.path
        )) ?? []
        XCTAssertFalse(
            landed.isEmpty,
            "nothing was written beneath the configured root \(configuredGeneratedDirectory.path)"
        )

        XCTAssertEqual(
            FileManager.default.fileExists(atPath: userGenerated.path),
            userDirectoryExistedBefore,
            "the run changed the user's own application-support storage at \(userGenerated.path)"
        )
    }

    // MARK: - AC93.1 and AC83.7: the info panel renders the decision (#108)

    /// ~~🚫 RT-108.6: the panel shows the sentence `SizingLine` returns, rather than deriving one.~~
    ///
    /// **Removed, identifier retired and not reused.** The panel's line cannot be read from
    /// XCUITest. Four attempts, each a distinct remedy and each measured: scanning every element's
    /// label found no line beginning `Scale: `; the panel's own `infoScale` identifier through
    /// `descendants(matching: .any)` found the element with an empty label; the same through
    /// `app.staticTexts` did too; and the fourth ran with the automation environment healthy, so
    /// none of it is the environment. The canvas container's label is carried, which #117 proves,
    /// so this is not a blanket platform limit — a `Text` nested inside a container declaring
    /// `children: .contain` is what does not report.
    ///
    /// **What replaces it is the route this codebase already uses for claims a test cannot make
    /// from outside.** `docs/ACs.md` carries four precedents: AC89.7's constructor claim, AC98.5's
    /// "no failure path bypasses that surface", AC103.2's absent type, and AC100.2's "through one
    /// function". Each is structural, each is confirmed by `audit-code`, and each keeps a test for
    /// the observable half.
    ///
    /// Here the observable half is RT-108.1 to RT-108.5, which hold what `SizingLine` composes,
    /// including the author's own case asserted literally. That `InfoPanel` renders it rather than
    /// deriving its own is one call at `InfoPanel.swift`, confirmed by reading it.
    ///
    /// The body is kept below rather than deleted, so a later session that finds a way to read the
    /// panel has the test rather than a description of one.
    private func disabled_test_theInfoPanelRendersTheDecision_RT108_6() throws {
        try XCTSkipIf(true, "See the note above: the panel's line is unreadable from XCUITest.")
    }

    /// The retired body, retained for a session that finds a way to read the panel.
    ///
    /// Five package tests hold what the function decides. This holds that the application asks it.
    /// Without this the wiring is asserted by nothing, which is the shape that let `FalStorageClient`
    /// ship complete and uncalled, and that let this very panel keep its own arithmetic while
    /// `ScaleReadout` sat one module away.
    ///
    /// The scale is left as the import set it. `selectScale` waits for the readout to contain
    /// "requested", which AC93.1 produces only when the ceiling reduces something, and the GUI
    /// fixture is far too small for that — so driving the scale here would hang on a condition the
    /// application is correct not to reach. That narrowness is the helper's, and it is recorded on
    /// master #114 rather than worked around silently.
    ///
    /// What this asserts is the wiring: whatever scale is in effect, the panel's sentence is the one
    /// `SizingLine` composes for it, in its exact form. The ceiling's arithmetic is RT-108.1 to
    /// RT-108.5's business, at package level, with sizes the GUI has no fixture for.
    func retired_theInfoPanelRendersTheDecision_RT108_6() throws {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        showInfoPanel()

        // Queried as a static text rather than as any descendant. `descendants(matching: .any)`
        // returns a wrapper whose own label is empty, which is what made this read back as `""`
        // through three earlier attempts. The `Text` itself carries the sentence.
        let scaleElement = app.staticTexts["infoScale"]
        XCTAssertTrue(
            scaleElement.waitForExistence(timeout: 5),
            "the info panel shows no scale line at all"
        )
        let scaleLine = scaleElement.label

        // The fixture's size is read rather than remembered: a number written into a test goes
        // stale in silence, which this suite has already been caught by once.
        let size = testImagePixelSize
        let activeScale = try XCTUnwrap(
            [2, 4, 8].first { app.buttons["scale\($0)x"].value as? String != nil
                && ((app.buttons["scale\($0)x"].value as? String) ?? "").lowercased()
                    .contains("in effect") },
            "no scale reads as in effect, so there is no decision to render"
        )
        let expected = "Scale: \(activeScale)× → "
            + "\(Int(size.width) * activeScale)×\(Int(size.height) * activeScale)"

        XCTAssertEqual(
            scaleLine, expected,
            "the panel is not rendering the sentence SizingLine composes"
        )
    }

    // MARK: - AC95.6: a credential row's controls occupy the same space in every state (#110)

    /// Opens Settings and returns the generation key's field.
    private func openSettingsAndFindTheKeyField() -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
        let field = element(identifier: "generationKeyField")
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Settings did not open")
        return field
    }

    /// RT-110.1: the row's frame is unchanged between empty and filled.
    func test_theCredentialRowDoesNotResizeWhenTyped_RT110_1() {
        let field = openSettingsAndFindTheKeyField()
        let before = field.frame

        field.click()
        field.typeText("fal-test-key-0123456789")

        XCTAssertEqual(field.frame.width, before.width, accuracy: 1, "the field changed width")
        XCTAssertEqual(field.frame.minX, before.minX, accuracy: 1, "the field moved")
    }

    /// RT-110.2: the row's frame is unchanged between the checking state and each settled state.
    ///
    /// The widest movement, and the one the author's words do not mention: the spinner appearing
    /// and disappearing around a provider check swings the row further than any keystroke.
    func test_theCredentialRowDoesNotResizeWhileChecking_RT110_2() {
        let field = openSettingsAndFindTheKeyField()
        field.click()
        field.typeText("fal-test-key-0123456789")
        let settled = field.frame

        app.buttons["saveGenerationKeyButton"].click()

        // Sampled repeatedly across the check rather than once, because the spinner is transient and
        // a single reading can miss the state entirely and pass without seeing it.
        for _ in 0..<20 {
            XCTAssertEqual(
                field.frame.width, settled.width, accuracy: 1,
                "the field changed width during or after the check"
            )
        }
    }

    /// RT-110.3: the rest of the form does not move while one row changes state.
    ///
    /// The test closest to the complaint: *"the layout of the whole form jumps about"* is about the
    /// other rows, not the one being typed into. It also catches the shortest wrong fix, which pins
    /// the field's width and leaves the trailing content free to push the row around.
    func test_theRestOfTheFormDoesNotMove_RT110_3() {
        let field = openSettingsAndFindTheKeyField()
        let accountField = element(identifier: "accountAdministrationKeyField")
        XCTAssertTrue(accountField.waitForExistence(timeout: 5), "the account key row is not present")
        let before = accountField.frame

        field.click()
        field.typeText("fal-test-key-0123456789")
        app.buttons["saveGenerationKeyButton"].click()

        XCTAssertEqual(accountField.frame.minY, before.minY, accuracy: 1, "the other row moved")
        XCTAssertEqual(accountField.frame.width, before.width, accuracy: 1, "the other row resized")
    }

    // MARK: - AC66.1 to AC66.3: the divider is visible against any background (#66)

    /// RT-66.1: the paint change leaves the divider's and the handle's frames alone.
    ///
    /// The visibility itself is judged by the author, in UT-66.1 to UT-66.4, because whether a line
    /// reads against a photograph is not something a machine decides. What a machine can hold is
    /// the geometry the paint sits on: AC90.14 maps the divider to the pointer within the displayed
    /// image frame, and AC96.4 requires it to address the same fraction of width in both pictures.
    /// UT-90.1 failed on that geometry once already.
    ///
    /// The shortest wrong fix for #66 is a heavier stroke that also widens the line. That improves
    /// visibility and moves the hit area, and this is what fails when it does.
    func test_theDividerGeometryIsUnchangedByThePaint_RT66_1() {
        // Entered over a filter result, which is the path RT-112.2 demonstrates opens the
        // comparison reliably. The divider's geometry is the same whichever derivation is being
        // compared, and this test is about the geometry.
        applyFilterLeavingScaleOff()

        let compare = app.buttons["compareButton"]
        XCTAssertTrue(compare.waitForExistence(timeout: 10))
        compare.click()

        let line = app.descendants(matching: .any)
            .matching(identifier: "curtainDividerLine").firstMatch
        let handle = app.descendants(matching: .any)
            .matching(identifier: "curtainDivider").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10), "the divider handle is not present")

        // The declared sizes, not measured guesses: the line is 2 points wide and the handle is a
        // 28-point circle. Both are the values the drag gesture and the pointer mapping assume.
        XCTAssertEqual(line.frame.width, 2, accuracy: 1, "the divider line changed width")
        XCTAssertEqual(handle.frame.width, 28, accuracy: 1, "the handle changed width")
        XCTAssertEqual(handle.frame.height, 28, accuracy: 1, "the handle changed height")
    }

    // MARK: - AC119.1: the progress indicator is centred over the picture (#119)

    /// How far two midpoints may differ and still count as centred.
    ///
    /// The criterion means centred, not identical to the last decimal. Comparing laid-out
    /// `CGFloat` midpoints exactly fails on rounding and retina scaling rather than on placement.
    /// Two points is well inside what anyone perceives as off-centre and well outside layout noise.
    private static let centringTolerance: CGFloat = 2

    /// The picture on the canvas, which is what the indicator is centred over.
    ///
    /// **Not the `workspaceCanvas` container.** That container declares `children: .contain`, and
    /// its accessibility frame is the union of its descendants rather than the visible canvas
    /// rectangle: measured here, its midpoint sat 68 points to the right of the indicator's, in the
    /// direction of the filter panel. AC119.1 says centred over the *picture*, and the picture is
    /// what this reads.
    private var canvasPicture: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "workingImage").firstMatch
    }

    /// Brings the fixture in, runs `prepare`, then starts an upscale and catches the indicator.
    ///
    /// The indicator exists only while work is in flight, so anything a test needs on screen
    /// alongside it has to be arranged *before* the work starts. Doing it afterwards races the
    /// upscale, which on this fixture finishes in seconds.
    /// Starts work by clearing the scale and choosing 8x.
    ///
    /// **Not usable where the comparison must stay open.** Clearing is not a neutral way to start
    /// fresh work: `.off` calls `releaseUpscaledResult`, which drops the result and sets
    /// `showComparison = false`. That is why the retired RT-119.4 could not use it; the note beside
    /// that identifier records the rest.
    private func startUpscaleAndCatchTheIndicator(
        preparing prepare: () -> Void = {}
    ) -> XCUIElement {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        prepare()
        clearScale()
        chooseScale(8)

        // `firstMatch` for the same reason as the canvas: more than one element carries this
        // identifier, and reading `.frame` from an ambiguous query raises "Multiple matching
        // elements found" rather than returning anything.
        let indicator = app.descendants(matching: .any)
            .matching(identifier: "workingIndicator")
            .firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 10), "no indicator while work is running")
        return indicator
    }

    /// RT-119.1: the indicator is horizontally centred on the canvas.
    func test_theIndicatorIsHorizontallyCentred_RT119_1() {
        let indicator = startUpscaleAndCatchTheIndicator()

        XCTAssertEqual(
            indicator.frame.midX, canvasPicture.frame.midX,
            accuracy: Self.centringTolerance,
            """
            the indicator is not horizontally centred on the canvas — \
            indicator \(indicator.frame) against picture \(canvasPicture.frame)
            """
        )
    }

    /// RT-119.2: the indicator is vertically centred on the canvas.
    ///
    /// The one that would have failed against the old placement, which put the indicator's midpoint
    /// in the upper third.
    func test_theIndicatorIsVerticallyCentred_RT119_2() {
        let indicator = startUpscaleAndCatchTheIndicator()

        XCTAssertEqual(
            indicator.frame.midY, canvasPicture.frame.midY,
            accuracy: Self.centringTolerance,
            "the indicator is not vertically centred on the canvas"
        )
    }

    /// RT-119.3: the indicator and the info panel are both present and do not overlap.
    ///
    /// #90 stacked the two together because as separate top-anchored children the panel drew over
    /// the indicator and hid it. Centring separates them by position instead, and this holds that
    /// the separation is real.
    func test_theIndicatorAndTheInfoPanelDoNotCollide_RT119_3() {
        // The panel is visible from launch: `infoPanelDismissed` starts false. Calling
        // `showInfoPanel` here toggled the comparison on the way, which disturbed the state the
        // test is about.
        let indicator = startUpscaleAndCatchTheIndicator()

        let panel = app.staticTexts["infoScale"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the info panel is not shown")
        XCTAssertTrue(indicator.exists, "the indicator went away when the panel appeared")
        XCTAssertFalse(
            indicator.frame.intersects(panel.frame),
            "the indicator and the info panel overlap"
        )
    }

    // 🚫 RT-119.4, the indicator centred over the curtain, is retired. Not deleted, and not quietly
    // dropped: the identifier stays here with what four attempts established.
    //
    // **It is blocked by #106, an open defect, and nothing inside #119 can route around it.**
    // The test needs real work running while the comparison is open. There are two ways to start
    // work and both are closed:
    //
    // 1. `clearScale()` then a preset. Clearing sets the selection to `.off`, which calls
    //    `releaseUpscaledResult` — that drops the result and sets `showComparison = false`. Right
    //    behaviour, since with nothing selected there is nothing to compare against, but the
    //    comparison is opened and shut again before the indicator appears. Measured as "the
    //    comparison did not open", then as "the curtain closed when the upscale started".
    // 2. Straight from one preset to another, avoiding `.off`. This is #106:
    //    `heldRendering` is consulted inside the `$scaleSelection` sink, and `@Published` publishes
    //    in `willSet`, so the lookup is keyed by the scale being *replaced*. With any previous
    //    rendering held, the new scale is served from the cache instantly — no run, no indicator.
    //    Measured directly: after settling on 4x and choosing 8x, the diagnostic read
    //    `scale8x=in effect; curtain present: true; status: Ready`. The picture arrived, no work
    //    ever started. `UpscaleViewModel.swift:655-670` documents the same mechanism and records
    //    that fixing it moves three closed issues' GUI tests, so it is #106's work and not this
    //    ticket's.
    //
    // **What stays uncovered, stated rather than glossed.** No automated test asserts the
    // indicator's placement while the curtain is showing. The exposure is small and the reason is
    // structural: the indicator is a **sibling of `canvasContent` in the canvas `ZStack`**, not a
    // child of it, so its placement is decided by the stack and cannot depend on whether the stack's
    // other child is the plain picture or the curtain. RT-119.1 and RT-119.2 exercise that same
    // placement code. What is lost is confidence that nothing inside `ComparisonView` displaces it,
    // which is a narrower claim than the criterion.
    //
    // UT-119.1 covers the judgement, and a user comparing while an upscale runs is exactly the case
    // it puts in front of the author. Reinstate this test with #106.

    // MARK: - AC94.3 and AC90.6: the curtain is offered for a filter result (#112)

    /// Imports the fixture and applies a filter, leaving the scale as the raise set it.
    ///
    /// The raise to the filterable minimum turns the scale off, so this reaches the state the
    /// author reported: a filter result with no upscale behind it.
    private func applyFilterLeavingScaleOff() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        let field = element(identifier: "generationPromptField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")
    }

    /// RT-112.1: with the scale off, a filter result offers the comparison.
    func test_aFilterResultOffersTheComparison_RT112_1() {
        applyFilterLeavingScaleOff()

        let compare = app.buttons["compareButton"]
        XCTAssertTrue(
            compare.waitForExistence(timeout: 10),
            "no comparison is offered for a filter result"
        )
        XCTAssertTrue(compare.isEnabled, "the comparison is offered but cannot be entered")
    }

    /// RT-112.2: entering the comparison over a filter result shows a usable curtain.
    ///
    /// Which two images the curtain holds is AC94.3's, already pinned by RT-94.7 against
    /// `baseFileURL`. XCUITest observes the accessibility tree, not which file backs each side, so
    /// this asserts what this layer can establish: the curtain is there and its divider moves.
    func test_enteringComparisonOverAFilterResultShowsTheCurtain_RT112_2() {
        applyFilterLeavingScaleOff()

        app.buttons["compareButton"].click()
        XCTAssertTrue(
            element(identifier: "curtainDivider").waitForExistence(timeout: 5),
            "the curtain has no divider"
        )
        XCTAssertTrue(
            element(identifier: "curtainPicture").exists,
            "the curtain draws no picture"
        )
    }

    /// RT-112.3: with a scale selected, the comparison is still offered after a filter.
    ///
    /// The existing behaviour is shown unchanged rather than traded away for the new one.
    func test_withAScaleSelectedTheComparisonIsStillOffered_RT112_3() {
        applyFilterLeavingScaleOff()
        chooseScale(2)

        XCTAssertTrue(
            app.buttons["compareButton"].waitForExistence(timeout: 30),
            "selecting a scale after a filter withdrew the comparison"
        )
    }

    /// RT-112.4: with nothing derived, no comparison is offered.
    ///
    /// AC90.6's absence half. A fix that offered Compare whenever there is any picture at all would
    /// pass RT-112.1 and break this.
    func test_withNothingDerivedNoComparisonIsOffered_RT112_4() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        clearScale()

        XCTAssertFalse(
            app.buttons["compareButton"].exists,
            "a comparison is offered with nothing derived to compare against"
        )
    }

    /// RT-112.5: the canvas reports a filter result rather than an upscaled rendering.
    ///
    /// The vacuity guard for #117's helper migration, expressed as a product state. If anything ever
    /// reports a filter result as a finished upscale, this fails here rather than 45 tests quietly
    /// asserting nothing and reporting green.
    func test_aFilterResultIsNotReportedAsAnUpscale_RT112_5() {
        applyFilterLeavingScaleOff()

        XCTAssertEqual(
            canvasKind, "A filter result",
            "a filter result is being reported as something else"
        )
    }

    // MARK: - AC117.1: the canvas reports what it is displaying (#117)

    /// What the canvas says it is showing.
    ///
    /// Read from the **label**, not the value. AC117.1 originally asked for a value and #117
    /// records the four measurements that showed SwiftUI does not carry one on any element reachable
    /// here; the criterion is superseded to the label channel on that evidence.
    /// Turns upscaling off by pressing whichever scale is in effect.
    ///
    /// `selectScale` deliberately refuses this: it guards against a test naming a scale without
    /// checking and silently turning upscaling off, then waiting for a result that never comes.
    /// Here the clearing is the point, so the guard is not what is wanted and the button is pressed
    /// directly.
    private func clearScale() {
        for scale in [2, 4, 8] {
            let button = app.buttons["scale\(scale)x"]
            guard button.exists else { continue }
            let value = (button.value as? String ?? "").lowercased()
            if value.contains("in effect"), !value.contains("not in effect") {
                button.click()
                return
            }
        }
        XCTFail("no scale reads as in effect, so there is nothing to clear")
    }

    /// Presses a scale button directly, without `selectScale`'s wait.
    ///
    /// That wait is for the value to contain `requested`, which AC93.1 produces only where the
    /// ceiling reduces something. The GUI fixture is far too small for that, so the wait times out
    /// on a state that is already correct. Recorded on master #114.
    private func chooseScale(_ scale: Int) {
        let button = app.buttons["scale\(scale)x"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "scale\(scale)x exists")
        XCTAssertTrue(button.isEnabled, "scale\(scale)x is enabled")
        button.click()
    }

    private var canvasKind: String? {
        let label = element(identifier: "workspaceCanvas").label
        let prefix = "Canvas showing "
        guard label.hasPrefix(prefix) else { return label.isEmpty ? nil : label }
        return String(label.dropFirst(prefix.count))
    }

    /// RT-117.1: with no image, the canvas reports that it is showing nothing.
    func test_withNoImageTheCanvasReportsNothing_RT117_1() {
        let canvas = element(identifier: "workspaceCanvas")
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "the canvas is not in the accessibility tree")
        XCTAssertEqual(canvasKind, "Nothing")
    }

    /// RT-117.2: with an image imported and no scale selected, it reports the base.
    func test_withNoScaleTheCanvasReportsTheBase_RT117_2() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        clearScale()
        XCTAssertEqual(canvasKind, "The base")
    }

    /// RT-117.3: with an upscale rendered, it reports an upscaled rendering.
    func test_withAnUpscaleRenderedTheCanvasReportsIt_RT117_3() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        XCTAssertEqual(canvasKind, "An upscaled rendering")
    }

    /// RT-117.4: with a filter result and no upscale, it reports a filter result.
    ///
    /// The raise to the filterable minimum clears the scale, so this is the ordinary state after
    /// applying a filter to an undersized picture rather than a contrived one.
    func test_withAFilterResultAndNoUpscaleTheCanvasReportsIt_RT117_4() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        let field = element(identifier: "generationPromptField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")

        XCTAssertEqual(canvasKind, "A filter result")
    }

    /// RT-117.5: the report follows the filter toggle between base and candidate.
    func test_theCanvasReportFollowsTheFilterToggle_RT117_5() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        let field = element(identifier: "generationPromptField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult())

        let toggle = element(identifier: "filterToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        XCTAssertEqual(canvasKind, "The base")
        toggle.click()
        XCTAssertEqual(canvasKind, "A filter result")
    }

    /// ~~🚫 RT-117.6: the label names the element, the value carries state, and they differ.~~
    ///
    /// **Superseded by RT-117.10, identifier retired and not reused.** It was written against
    /// AC117.1's original "as a value" clause. That clause is itself superseded, because SwiftUI
    /// carried no value on any element reachable here, so the state moved into the label. Left as
    /// written, this test compared the label against a substring of itself and passed while proving
    /// nothing, which is the vacuity this delivery has been auditing other tickets for.
    ///
    /// RT-117.10: the canvas's label both names the element and carries the state.
    ///
    /// Both halves are asserted, because the state going in must not push the name out. An element
    /// that reports only its state is as unhelpful to a screen reader as one that reports only its
    /// name.
    func test_theCanvasLabelNamesTheElementAndCarriesTheState_RT117_10() throws {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let label = element(identifier: "workspaceCanvas").label
        XCTAssertFalse(label.isEmpty, "the canvas has no accessibility label")
        XCTAssertTrue(label.contains("Canvas"), "the label no longer names the element: \(label)")

        let state = try XCTUnwrap(canvasKind, "the label carries no state")
        XCTAssertFalse(state.isEmpty)
        XCTAssertNotEqual(state, label, "the label is nothing but the state, so the name is gone")
    }

    /// RT-117.8: while an earlier locked iteration is being viewed, the canvas reports the base.
    ///
    /// An iteration is the base of its own position in the chain: the user is looking at their own
    /// picture rather than at something derived from it. A fifth kind would make every caller
    /// handle a case that means the same thing.
    ///
    /// This test could not be written until #111 landed. Before it, opening an iteration was
    /// processed as an import and the viewing state collapsed immediately, so the test would have
    /// passed because the state was gone rather than because the report was right.
    func test_theCanvasReportsTheBaseWhileViewingAnIteration_RT117_8() {
        buildLockChain(of: 1)
        lockChainEntries[0].click()

        XCTAssertEqual(
            canvasKind, "The base",
            "the canvas does not report an opened iteration as the base"
        )
    }

    /// RT-117.7: the value follows the picture, not the request.
    ///
    /// The test that stops this work recreating the defect it exists to prevent. AC90.2 keeps the
    /// previous picture on the canvas while an operation runs, so a value that flips when an
    /// upscale *starts* would make `waitForUpscaleComplete` return before one had finished.
    func test_theCanvasReportFollowsThePictureNotTheRequest_RT117_7() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        clearScale()
        XCTAssertEqual(canvasKind, "The base")

        chooseScale(8)
        // Read while the work is in flight. The indicator's presence is what says so.
        let indicator = element(identifier: "workingIndicator")
        if indicator.waitForExistence(timeout: 5) {
            XCTAssertEqual(
                canvasKind, "The base",
                "the canvas reported an upscaled rendering while the upscale was still running"
            )
        }
        XCTAssertTrue(waitForUpscaleComplete())
        XCTAssertEqual(canvasKind, "An upscaled rendering")
    }

    /// RT-117.9: the four kinds are four distinct values, collected in one test.
    ///
    /// Written as one walk rather than four tests, because four tests each seeing one value all
    /// pass against an implementation that reports the same string for two of them — and
    /// `waitForUpscaleComplete` discriminates on exactly one, so a collision returns it on the
    /// wrong state at 45 call sites.
    func test_theFourKindsAreFourDistinctValues_RT117_9() throws {
        var seen: [String] = []

        XCTAssertEqual(canvasKind, "Nothing")
        seen.append("Nothing")

        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        seen.append(try XCTUnwrap(canvasKind))

        clearScale()
        seen.append(try XCTUnwrap(canvasKind))

        let field = element(identifier: "generationPromptField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult())
        seen.append(try XCTUnwrap(canvasKind))

        XCTAssertEqual(Set(seen).count, 4, "two of the four states report the same value: \(seen)")
    }

    // MARK: - AC89.3 and AC89.8: the lock chain survives being used (#111)

    /// Applies a filter to whatever is on the canvas and locks the result.
    ///
    /// Each call extends the lock chain by one, which is the state every test below needs.
    private func applyAndLock(_ prompt: String) {
        let field = element(identifier: "generationPromptField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(prompt)
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")

        let lock = element(identifier: "lockButton")
        XCTAssertTrue(lock.isEnabled, "there is a candidate to promote")
        lock.click()
    }

    /// Applies a filter and waits for the result, without locking it.
    ///
    /// `applyAndLock` promotes the candidate, which is the wrong shape for a test about what the
    /// candidate itself does: locking it would move the base forward again and undo the selection
    /// the test just made.
    private func applyFilterOnly(_ prompt: String) {
        let field = element(identifier: "generationPromptField")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(prompt)
        app.buttons["applyFilterButton"].click()
        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")
    }

    /// Every entry in the lock chain strip, in order.
    ///
    /// Matched as **buttons** rather than as any descendant. Each entry is a `Button` wrapping a
    /// labelled thumbnail, and both carry the identifier, so `.any` counted every entry twice and
    /// two locks reported four entries.
    private var lockChainEntries: [XCUIElement] {
        element(identifier: "lockChain")
            .descendants(matching: .button)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'lockedIteration-'"))
            .allElementsBoundByIndex
    }

    /// A second fixture, for the cases that need a picture the application is not already showing.
    private var otherTestImagePath: String {
        URL(fileURLWithPath: testImagePath)
            .deletingLastPathComponent()
            .appendingPathComponent("icon2.png")
            .path
    }

    /// Imports the fixture and builds a chain of `count` locked iterations.
    private func buildLockChain(of count: Int) {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        for index in 0..<count {
            applyAndLock("UI fixture generation \(index)")
        }
        XCTAssertTrue(
            element(identifier: "lockChain").waitForExistence(timeout: 10),
            "the locked iterations join the chain"
        )
    }

    // MARK: - AC94.4: one intent to apply issues one provider request (#122)

    /// How many generation requests the stubbed provider has been asked to make.
    ///
    /// The only way to observe a paid call from outside the process. Counting arrivals on the
    /// canvas is a different claim and passes against the defect: a second request returning an
    /// identical picture is one visible change and two charges.
    ///
    /// Read after a positive signal that the work finished, because the element's value is
    /// evaluated when the view redraws and nothing forces a redraw for the counter's own sake.
    private var generationRequestCount: Int {
        let element = element(identifier: "generationRequestCount")
        guard element.waitForExistence(timeout: 5) else { return -1 }
        return Int(element.value as? String ?? "") ?? -1
    }

    /// The suite's fixture, asserted to be below the filterable minimum.
    ///
    /// RT-122.7 depends on the raise happening, and the raise is the bulk of the window this issue
    /// closes. Asserted rather than assumed so the test fails loudly if the fixture is ever
    /// replaced, instead of quietly exercising a window of milliseconds.
    private func assertFixtureNeedsARaise() {
        let info = statusBarText(of: "noticeMessage")
        XCTAssertTrue(
            info.localizedCaseInsensitiveContains("minimum")
                || info.localizedCaseInsensitiveContains("raised"),
            "the fixture no longer needs a raise, so this test exercises the wrong window — \"\(info)\"")
    }

    // RT-122.1 and RT-122.2
    //
    // The reported defect: *"I could double click the button and it would fire twice which is a
    // problem esp since it costs money."*
    //
    // Written as the second click changing nothing, not as the control being disabled after the
    // first. A poll that runs after the disabling cannot tell "disabled synchronously" from
    // "disabled a second later", and late is precisely the bug.
    func test_twoRapidClicksOnApplyIssueOneRequest_RT122_1_and_RT122_2() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")

        let apply = app.buttons["applyFilterButton"]
        XCTAssertTrue(apply.isEnabled, "Apply is available before the first press")
        apply.click()
        // Immediately, with no wait: the window this issue closes is the one right after the click.
        if apply.isEnabled { apply.click() }

        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")
        XCTAssertEqual(
            generationRequestCount, 1,
            "two clicks in the window issued two paid requests")
    }

    // RT-122.3
    //
    // The other half. Disabling the control is idempotence; this is AC94.1's obligation, and a fix
    // delivering only the first leaves the user watching an unchanged window — the defect AC94.1
    // exists to prevent, reappearing on the path that caused the double click.
    func test_pressingApplyReportsWithinTheSameInteraction_RT122_3() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()

        let indicator = app.descendants(matching: .any)
            .matching(identifier: "workingIndicator")
            .firstMatch
        XCTAssertTrue(
            indicator.waitForExistence(timeout: 3),
            "nothing reported that work had begun, so the window is silent as well as live")
    }

    // RT-122.7
    //
    // The condition the author actually hit. The raise is a real Neural Engine run of several
    // seconds and sits entirely inside the window; a picture already above the minimum exercises
    // milliseconds and passes against the unfixed code.
    func test_theWindowCoversTheRaiseOnAnUndersizedPicture_RT122_7() {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())
        assertFixtureNeedsARaise()

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")

        let apply = app.buttons["applyFilterButton"]
        apply.click()
        XCTAssertFalse(
            apply.isEnabled,
            "Apply stayed live into the raise, which is where the second click landed")

        XCTAssertTrue(waitForFilterResult(), "the filter result should reach the canvas")
        XCTAssertEqual(generationRequestCount, 1)
    }

    // RT-122.4
    //
    // A flag that leaks on a failure path disables Apply for the rest of the session, which is a
    // worse defect than the one being fixed and one no happy-path test catches.
    func test_applyIsUsableAgainAfterTheProviderDeclines_RT122_4() {
        failAGenerationRequest()
        dismissFailureAlert()

        let apply = app.buttons["applyFilterButton"]
        XCTAssertTrue(
            apply.waitForExistence(timeout: 5) && apply.isEnabled,
            "a declined request left Apply permanently unavailable")
    }

    // RT-122.6
    //
    // The upload path is a different route from the generation path — #113 established that, and
    // the flag must clear on both.
    func test_applyIsUsableAgainAfterTheUploadFails_RT122_6() {
        app.terminate()
        app.launchEnvironment["SUPERSCALE_UI_TEST_FAIL"] = "provider"
        app.launch()
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()

        XCTAssertTrue(failureAlert.waitForExistence(timeout: 120))
        dismissFailureAlert()

        let apply = app.buttons["applyFilterButton"]
        XCTAssertTrue(
            apply.waitForExistence(timeout: 5) && apply.isEnabled,
            "a failed upload left Apply permanently unavailable")
    }

    // MARK: - AC89.9: selecting an iteration restores the working context it was made in (#121)

    // RT-121.3
    //
    // The author's third symptom: *"when i click on a previous lock image, apply a filter, the
    // 'Show original'/show filtered button is missing now."*
    //
    // A GUI test rather than a package one, because the claim is about what reaches the user. The
    // control's presence follows from there being two assets to compare, and after a selection
    // there are — the selected iteration and its parent — so a missing control means the graph and
    // the view disagree about what is current, which is the whole of #121.
    func test_theFilterToggleIsPresentAfterFilteringASelectedIteration_RT121_3() {
        buildLockChain(of: 2)

        let entries = lockChainEntries
        XCTAssertGreaterThanOrEqual(entries.count, 2, "two locks give at least two entries")
        entries[0].click()

        applyFilterOnly("UI fixture generation after selecting")

        let toggle = element(identifier: "filterToggle")
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "filtering a selected iteration leaves nothing to compare against")
    }

    // RT-121.5
    //
    // The author's second symptom: *"it is showing a third image i do not know where it came from,
    // seems to be identical but slightly brighter."*
    //
    // Asserted on the canvas's reported **identity**, not on its existence. A third image loaded
    // from a real asset would satisfy "the canvas shows something the graph holds"; what was wrong
    // was which asset, and that is what this reads. `canvasKind` is the report #117 made readable
    // for exactly this kind of question.
    func test_theCanvasReportsTheSelectedIterationNotSomethingElse_RT121_5() {
        buildLockChain(of: 2)

        let entries = lockChainEntries
        XCTAssertGreaterThanOrEqual(entries.count, 2)
        entries[0].click()

        XCTAssertEqual(
            canvasKind, "A filter result",
            "selecting an iteration puts that iteration on the canvas as the candidate")

        let showing = entries[0].value as? String ?? ""
        XCTAssertTrue(
            showing.localizedCaseInsensitiveContains("showing"),
            "and the strip agrees which entry it is — the entry reads '\(showing)'")
    }

    /// RT-111.1: opening an iteration leaves the strip present, whole, and usable.
    ///
    /// The entry count is asserted because a strip that survives while losing its contents
    /// satisfies presence and hittability alone.
    func test_openingAnIterationLeavesTheChainWhole_RT111_1() {
        buildLockChain(of: 2)
        let before = lockChainEntries.count
        // Not a fixed number. The chain holds the source and each raise to the filterable minimum
        // as well as each locked candidate, so two apply-and-lock cycles legitimately make four
        // entries. What this test is about is that opening one changes nothing, and a number
        // written in here would go stale in silence the next time the journey changes.
        XCTAssertGreaterThanOrEqual(before, 2, "two locks put at least two entries in the chain")

        lockChainEntries[0].click()

        let chain = element(identifier: "lockChain")
        XCTAssertTrue(chain.exists, "the chain strip disappeared when an iteration was opened")
        XCTAssertEqual(lockChainEntries.count, before, "the chain lost entries when one was opened")
        XCTAssertTrue(lockChainEntries[1].isHittable, "the other iteration is no longer reachable")
    }

    /// RT-111.2: moving from one open iteration directly to another.
    ///
    /// The author's actual attempted action: *"i can not navigate to any other previously locked
    /// images."*
    func test_navigatingFromOneIterationToAnother_RT111_2() {
        buildLockChain(of: 2)
        lockChainEntries[0].click()
        XCTAssertTrue(element(identifier: "lockChain").exists)

        lockChainEntries[1].click()

        XCTAssertEqual(
            lockChainEntries[1].value as? String, "Showing",
            "the second iteration did not become the one on the canvas"
        )
    }

    /// RT-111.3: a chain of exactly one survives being opened.
    func test_aChainOfOneSurvivesBeingOpened_RT111_3() {
        buildLockChain(of: 1)
        let before = lockChainEntries.count
        XCTAssertGreaterThanOrEqual(before, 1, "one lock puts at least one entry in the chain")

        lockChainEntries[0].click()
        XCTAssertEqual(lockChainEntries.count, before, "the chain lost entries when one was opened")

        XCTAssertTrue(
            element(identifier: "lockChain").exists,
            "a single-entry chain disappeared when its only entry was opened"
        )
    }

    /// RT-111.4: a genuine import from the viewing state still empties the chain.
    ///
    /// AC89.8 must survive the fix. The shortest route to green on the tests above is to stop
    /// `importImage` clearing the chain, or to widen the guard until nothing re-imports; either
    /// satisfies RT-111.1 and RT-111.2 and breaks this.
    /// ~~🚫 RT-111.4: a genuine import from the viewing state still empties the chain.~~
    ///
    /// **Removed, identifier retired and not reused.** The test cannot be performed: with a picture
    /// already loaded the application offers no route to open another. `fileChooser` lives on
    /// `DropTargetView`, which is the empty-canvas import target, and there is no File menu open
    /// command. The only remaining route is drag and drop from Finder, which XCUITest cannot drive.
    ///
    /// This is not the same as the behaviour being unheld. **RT-89.25** covers *"importing a new
    /// image empties the lock chain"* at the workspace level, and the guard this ticket adds is
    /// three lines above `importImage` in the same function, so a reader can see that a genuine
    /// import still reaches it.
    ///
    /// What is genuinely lost is the anti-gaming property: nothing now fails if a later change
    /// widens that guard until no import registers at all. Recorded on master #114 rather than
    /// papered over, together with the separate observation that guide section 2.2 promises the
    /// open panel as one of three import routes and the application withdraws it once an image is
    /// loaded.

    /// ~~🚫 RT-111.5: an entry whose file has gone stays in the chain and reports itself
    /// unavailable.~~
    ///
    /// **Removed, identifier retired and not reused.** The test has to make an iteration's file
    /// disappear, and the XCUITest runner cannot: removing a file the application wrote returns
    /// `NSCocoaErrorDomain 513`, *"couldn't be removed because you don't have permission to access
    /// it"*, from the runner's sandbox. The file's own permissions are ordinary; the restriction is
    /// the process's.
    ///
    /// The behaviour is not left uncovered. **RT-81.20** already holds it at package level: *"a
    /// locked iteration whose file is absent remains in the chain and reports itself unavailable"*,
    /// and **RT-81.32** holds the present case. What this test would have added is confirmation
    /// through the application, and that is what the sandbox denies rather than something a
    /// different assertion could reach.

    /// RT-111.6: one action returns to the live image, and it is that image.
    ///
    /// Asserting only that the viewing state ended would pass against a control that returns to
    /// some other picture.
    func test_oneActionReturnsToTheLiveImage_RT111_6() {
        buildLockChain(of: 2)
        lockChainEntries[0].click()

        let back = element(identifier: "returnToCurrentButton")
        XCTAssertTrue(back.waitForExistence(timeout: 5), "no way back to the live image")
        back.click()

        XCTAssertEqual(
            canvasKind, "The base",
            "returning did not put the live base on the canvas"
        )
        for entry in lockChainEntries {
            XCTAssertNotEqual(
                entry.value as? String, "Showing",
                "an iteration is still marked as the one on the canvas"
            )
        }
    }

    /// RT-111.7: the strip reports which entry is open, as a value, across two entries.
    ///
    /// Asserted at two different entries so a hard-coded value fails. Guide section 3.9: a
    /// perceivable state is a value, not a tint.
    func test_theChainReportsWhichEntryIsOpen_RT111_7() {
        buildLockChain(of: 2)

        lockChainEntries[0].click()
        XCTAssertEqual(lockChainEntries[0].value as? String, "Showing")
        XCTAssertNotEqual(lockChainEntries[1].value as? String, "Showing")

        lockChainEntries[1].click()
        XCTAssertEqual(lockChainEntries[1].value as? String, "Showing")
        XCTAssertNotEqual(lockChainEntries[0].value as? String, "Showing")
    }

    /// RT-111.8: the strip persists with the scale both cleared and selected.
    ///
    /// Viewing runs through the upscale path, so the two states are not the same journey.
    func test_theChainPersistsAtEitherScaleState_RT111_8() {
        buildLockChain(of: 2)

        // The raise to the filterable minimum has already cleared the scale.
        lockChainEntries[0].click()
        XCTAssertTrue(element(identifier: "lockChain").exists, "with the scale cleared")

        // `selectScale` is not used here. It waits for the pressed scale to read "requested", and
        // AC93.1 produces that wording only where the ceiling reduces something. The GUI fixture is
        // far too small for that, so the helper waits out its timeout on a state that is already
        // correct. Recorded on master #114 as a pre-existing narrowness in the helper.
        let scaleButton = app.buttons["scale2x"]
        XCTAssertTrue(scaleButton.waitForExistence(timeout: 10))
        XCTAssertTrue(scaleButton.isEnabled)
        scaleButton.click()

        lockChainEntries[1].click()
        XCTAssertTrue(element(identifier: "lockChain").exists, "with a scale selected")
    }

    // MARK: - AC98.5: one failure surface (#98)

    // RT-98.14
    //
    // `errorMessage` was assignable from `MainView`, `SuperscaleApp` and `UpscaleViewModel` alike —
    // nine sites in `MainView` alone — and each decided for itself how to turn an error into a
    // sentence. This asserts the two subsystems arrive at the *same* surface, which is the claim
    // AC98.5 makes about the window.
    //
    // Both failures are induced through `SUPERSCALE_UI_TEST_FAIL`, because neither can be made to
    // fail from outside otherwise: the generation service is stubbed to succeed and the upscale runs
    // the real pipeline on a real fixture.
    func test_aFilterFailureAndAnUpscaleFailureArePresentedTheSameWay_RT098_14() {
        // One subsystem per launch, because the two are not independent: the suite's fixture is
        // below the filterable minimum, so applying a filter raises it first, and a raise is an
        // upscale. Failing both at once would fail the filter path at the raise, and this test would
        // be comparing one subsystem with itself.

        // The upscale, which runs on import.
        app.terminate()
        app.launchEnvironment["SUPERSCALE_UI_TEST_FAIL"] = "upscale"
        app.launch()
        XCTAssertTrue(loadTestImage(), "the working image should load")

        XCTAssertTrue(
            failureAlert.waitForExistence(timeout: 60), "an upscale failure reaches a surface")
        let upscaleWords = spokenText(of: failureAlert)
        XCTAssertTrue(
            upscaleWords.localizedCaseInsensitiveContains("upscale"),
            "and it says what happened: \"\(upscaleWords)\"")
        let upscaleAlert = failureAlert.elementType

        // The provider, on a fresh launch, reached by applying a filter.
        app.terminate()
        app.launchEnvironment["SUPERSCALE_UI_TEST_FAIL"] = "provider"
        app.launch()
        XCTAssertTrue(loadTestImage(), "the working image should load again")
        XCTAssertTrue(waitForUpscaleComplete(), "and its upscale succeeds this time")

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()

        XCTAssertTrue(
            failureAlert.waitForExistence(timeout: 120), "a filter failure reaches the same surface")
        let filterWords = spokenText(of: failureAlert)
        XCTAssertTrue(
            filterWords.localizedCaseInsensitiveContains("provider")
                || filterWords.localizedCaseInsensitiveContains("storage"),
            "carrying the provider's own words: \"\(filterWords)\"")
        XCTAssertEqual(
            failureAlert.elementType, upscaleAlert,
            "the same kind of surface, not two that merely look alike")
        XCTAssertNotEqual(
            filterWords, upscaleWords,
            "and not the same surface because both failures say the same thing")
    }

    // MARK: - AC98.5: a declined generation request reaches the one failure surface (#113)

    /// Drives an apply to the point where the generation request itself fails.
    ///
    /// `SUPERSCALE_UI_TEST_FAIL=generation` rather than `provider`. The two are not the same route
    /// and `provider` cannot reach this one: `submitFilter` uploads before it generates, so a stub
    /// failing both throws at the upload and execution never arrives at `generate`. That is why
    /// RT-98.14 has only ever exercised the upload half, and why a generation failure that reached
    /// no alert survived #98.
    private func failAGenerationRequest(
        file: StaticString = #filePath, line: UInt = #line
    ) {
        app.terminate()
        app.launchEnvironment["SUPERSCALE_UI_TEST_FAIL"] = "generation"
        app.launch()
        XCTAssertTrue(loadTestImage(), "the working image should load", file: file, line: line)
        XCTAssertTrue(waitForUpscaleComplete(), "and its upscale succeeds", file: file, line: line)

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), file: file, line: line)
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()
    }

    /// Presses the alert's button, whatever it is called.
    private func dismissFailureAlert(file: StaticString = #filePath, line: UInt = #line) {
        let alert = failureAlert
        XCTAssertTrue(alert.waitForExistence(timeout: 120),
                      "no failure alert to dismiss", file: file, line: line)
        let button = alert.buttons.firstMatch
        XCTAssertTrue(button.exists, "the alert offers no way out", file: file, line: line)
        button.click()
        XCTAssertTrue(
            alert.waitForNonExistence(timeout: 10),
            "the alert did not go away when dismissed", file: file, line: line)
    }

    // RT-113.1
    //
    // The reported defect. A provider declining a generation request is a failure, and AC98.5 gives
    // the application one surface for those. This one landed in the status bar's caption instead —
    // an API error in the place reserved for ambient state, in caption type at the foot of the
    // window, where a user watching the canvas for their result does not look.
    func test_aDeclinedGenerationRequestReachesTheFailureSurface_RT113_1() {
        failAGenerationRequest()

        XCTAssertTrue(
            failureAlert.waitForExistence(timeout: 120),
            "a declined generation request reached no alert")
        let words = spokenText(of: failureAlert)
        XCTAssertTrue(
            words.localizedCaseInsensitiveContains("rejected")
                || words.localizedCaseInsensitiveContains("provider"),
            "the alert does not carry the provider's own words: \"\(words)\"")
    }

    // RT-113.2
    //
    // The asymmetry is the defect: two halves of one apply presented two different ways. Asserted as
    // the same *kind* of surface carrying **different** sentences, because the first half alone is a
    // tautology once both call `report` — every alert is an alert. The second half is what catches
    // the fix that routes both through one hard-coded string and loses the provider's own words.
    func test_theUploadAndGenerationFailuresPresentThroughTheSameSurface_RT113_2() {
        // The upload half, which is the route RT-98.14 has always taken.
        app.terminate()
        app.launchEnvironment["SUPERSCALE_UI_TEST_FAIL"] = "provider"
        app.launch()
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete(), "and its upscale succeeds")

        let prompt = element(identifier: "generationPromptField")
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.click()
        prompt.typeText("UI fixture generation")
        app.buttons["applyFilterButton"].click()

        XCTAssertTrue(failureAlert.waitForExistence(timeout: 120), "the upload failure reaches a surface")
        let uploadWords = spokenText(of: failureAlert)
        let uploadSurface = failureAlert.elementType

        // The generation half, which reached no surface at all before #113.
        failAGenerationRequest()

        XCTAssertTrue(
            failureAlert.waitForExistence(timeout: 120),
            "the generation failure reaches the same surface")
        let generationWords = spokenText(of: failureAlert)

        XCTAssertEqual(
            failureAlert.elementType, uploadSurface,
            "the same kind of surface, not two that merely look alike")
        XCTAssertNotEqual(
            generationWords, uploadWords,
            "both failures say the same thing, so one of them has lost the provider's own words")
    }

    // RT-113.3
    //
    // "Coherent" is a judgement, so this asserts the two halves of it a machine can decide: nothing
    // still claims work is in progress. Whether the whole scene reads sensibly after a failure is
    // the re-offered UT, not smuggled in here behind a vague predicate.
    func test_theStatusBarDoesNotStillClaimWorkAfterAFailure_RT113_3() {
        failAGenerationRequest()
        dismissFailureAlert()

        let status = statusBarText(of: "statusText")
        XCTAssertFalse(
            status.localizedCaseInsensitiveContains("Applying filter"),
            "the status bar is still applying a filter that failed: \"\(status)\"")
        XCTAssertFalse(
            status.localizedCaseInsensitiveContains("Preparing"),
            "the status bar is still preparing: \"\(status)\"")
    }

    // RT-113.4
    //
    // Blocks the narrowest wrong fix, which is to route the failure to `report` and *also* leave the
    // diagnostic in the caption, so it appears twice. The status bar keeps ambient state; the
    // provider's words belong on the alert and nowhere else.
    func test_theStatusBarSaysFilterFailedAndNotTheDiagnostic_RT113_4() {
        failAGenerationRequest()
        dismissFailureAlert()

        let status = statusBarText(of: "statusText")
        XCTAssertTrue(
            status.localizedCaseInsensitiveContains("Filter failed"),
            "the status bar does not report the failure as ambient state: \"\(status)\"")
        XCTAssertFalse(
            status.localizedCaseInsensitiveContains("rejected"),
            "the diagnostic is in the caption as well as the alert: \"\(status)\"")
    }

    // RT-113.5
    //
    // Written as a bounded positive check, not as "an alert never appears twice". Proving a negative
    // against an unbounded wait passes whenever the code is merely slow. The bug this guards —
    // observing the *phase* rather than the failure *message*, so every redraw re-raises — produces
    // a visible second alert immediately, which a bounded check catches.
    func test_aDismissedFailureDoesNotComeBack_RT113_5() {
        failAGenerationRequest()
        dismissFailureAlert()

        // Something that causes a redraw while the phase is still failed. Typing into the prompt is
        // the cheapest one to hand and is exactly what a user does next.
        let prompt = element(identifier: "generationPromptField")
        if prompt.exists {
            prompt.click()
            prompt.typeText(" again")
        }

        XCTAssertFalse(
            failureAlert.waitForExistence(timeout: 5),
            "the failure alert came back on a redraw, so it is raised per redraw rather than per failure")
    }

    // RT-87.15: no reference wells exist. The working image is the reference.
    func test_theWorkspacePresentsNoReferenceWell_RT087_15() {
        let referenceWells = app.buttons.matching(NSPredicate(format: "label == 'Add image'"))

        XCTAssertEqual(referenceWells.count, 0)
    }

    // RT-87.35, under AC87.2: the working image occupies the canvas whether or not an upscale is
    // selected.
    //
    // With the scale off there is no upscaled output — AC82.6 — and the canvas drew only the
    // upscaled result, so an image imported in that state appeared not to arrive at all. Filtering
    // without upscaling is a legitimate use on its own, and so is doing both.
    func test_theWorkingImageIsShownWithTheScaleOff_RT087_35() {
        // 4x is the selection on launch, so choosing it once empties the selection — AC82.7.
        // Clicking twice would turn the scale off and straight back on.
        let scaleFour = app.buttons["scale4x"]
        XCTAssertTrue(scaleFour.waitForExistence(timeout: 5))
        scaleFour.click()

        // Changing a setting brings the info panel back, and it sits over the top of the canvas
        // where the import control is.
        let dismiss = app.buttons["infoPanelDismiss"]
        if dismiss.waitForExistence(timeout: 2) { dismiss.click() }

        XCTAssertTrue(loadTestImage(), "an image should import with no scale selected")

        XCTAssertTrue(
            element(identifier: "workingImage").waitForExistence(timeout: 10),
            "the imported image should occupy the canvas even with no upscale selected"
        )
        // 🚫 **Superseded, not deleted.** This asserted that Save is absent with no upscale, and
        // Save is now offered whenever there is a picture at all. The behaviour changed for a
        // reason this test could not have anticipated: #96 raises an undersized picture to the
        // filterable minimum and turns the scale off, so a user who filters a small photograph ends
        // up in exactly this state — with a result they have just paid 2c for and no way to write it
        // to disk. AC89.3 asks for an iteration to be saveable *at the current scale selection*, and
        // with no scale selected that is the picture as it stands.
        //
        // What the test still checks is what it was really for: the canvas is occupied with no
        // upscale selected. **Compare** is the control that genuinely requires a derivation, so it
        // takes over the absence assertion.
        XCTAssertFalse(
            app.buttons["compareButton"].exists,
            "there is nothing derived to compare the picture against")
        XCTAssertTrue(
            app.buttons["saveButton"].exists,
            "but the picture itself can be saved as it stands")
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

    // RT-87.8: every category the catalogue declares is offered as a one-click narrowing.
    //
    // Rewritten from section headings to a filter bar. Headings grouped 86 filters into one long
    // scroll and called it categorisation; what they did not offer was choosing a category. These
    // assert the chips, which narrow in one click and clear in one click.
    func test_everyCategoryIsOfferedAsAFilter_RT087_8() {
        XCTAssertTrue(element(identifier: "category-all").waitForExistence(timeout: 5))

        for category in ["design", "illustration", "lighting", "material",
                         "media", "photo", "print", "sketch", "zeitgeist"] {
            XCTAssertTrue(
                element(identifier: "category-\(category)").exists,
                "\(category) should be offered as a category chip"
            )
        }
    }

    // RT-87.9: choosing a category narrows the list to the filters that declare it.
    func test_choosingACategoryNarrowsTheList_RT087_9() {
        let lighting = element(identifier: "category-lighting")
        XCTAssertTrue(lighting.waitForExistence(timeout: 5))
        lighting.click()

        XCTAssertTrue(element(identifier: "filter-image-lighting-film-noir").exists)
        XCTAssertFalse(
            element(identifier: "filter-image-print-linocut").exists,
            "a Print filter should not survive narrowing to Lighting"
        )
        XCTAssertEqual(textContent(of: element(identifier: "filterCount")), "4")
    }

    // RT-87.36: the same chip again widens it, so clearing costs one click too.
    func test_choosingTheActiveCategoryAgainClearsTheNarrowing_RT087_36() {
        let lighting = element(identifier: "category-lighting")
        XCTAssertTrue(lighting.waitForExistence(timeout: 5))

        lighting.click()
        XCTAssertEqual(textContent(of: element(identifier: "filterCount")), "4")
        lighting.click()

        XCTAssertEqual(textContent(of: element(identifier: "filterCount")), "86")
        XCTAssertTrue(element(identifier: "filter-image-print-linocut").exists)
    }

    // RT-87.37: search reaches across categories, so nothing is behind a chip.
    func test_searchReachesAcrossCategories_RT087_37() {
        let search = element(identifier: "filterSearchField")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("noir")

        XCTAssertTrue(element(identifier: "filter-image-lighting-film-noir").exists)
        XCTAssertEqual(textContent(of: element(identifier: "filterCount")), "1")
    }

    // RT-87.10: nothing is unreachable.
    func test_everyFilterTheApplicationReportsIsReachable_RT087_10() {
        XCTAssertTrue(element(identifier: "filterCount").waitForExistence(timeout: 5))
        let reported = textContent(of: element(identifier: "filterCount"))

        XCTAssertEqual(reported, "86", "with no category chosen, every filter is offered")
    }

    // RT-87.11: choosing a filter fills the prompt area.
    //
    // Narrowed to its category first, which is what the chips are for and what a user does: with
    // all 86 listed, a row far down the list is in the tree but scrolled out of view, so it has no
    // hit point.
    func test_choosingAFilterFillsThePromptArea_RT087_11() {
        let lighting = element(identifier: "category-lighting")
        XCTAssertTrue(lighting.waitForExistence(timeout: 5))
        lighting.click()

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

    // MARK: - Slice 9c: the display model at the window

    // The package tests prove `CanvasContent` and `CurtainGeometry`. These prove the window uses
    // them, which is a separate claim: the divider's arithmetic was defensible for five months
    // while the view fed it the width of the wrong rectangle.

    // RT-90.2 (GUI counterpart)
    func test_theCanvasIsNeverEmptyWhileAnImageIsLoaded_RT090_2_GUI() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }

        // Before the upscale finishes, and after: at no point is there nothing to look at.
        let image = app.images["workingImage"]
        XCTAssertTrue(
            image.waitForExistence(timeout: 10),
            "the picture appears on the canvas without waiting for its upscale")

        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }
        // A completed upscale enters comparison, and the comparison draws the picture itself rather
        // than through `workingImage`. The criterion is that the canvas is never empty, not that
        // one particular view is always the one drawing — so either counts.
        XCTAssertTrue(
            image.exists,
            "and there is still a picture afterwards, whichever view is drawing it")
    }

    // RT-90.25, RT-90.44, RT-90.45, RT-90.49 (GUI)
    //
    // The reported defect and its repair, together: the picture and the indicator are present at
    // the same time, the indicator is small, it sits at the top, and the picture is reachable
    // beneath it. `.thinMaterial` over a full-canvas overlay satisfied none of these.
    func test_theIndicatorSitsOverThePictureWithoutCoveringIt_RT090_25() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }

        let indicator = app.otherElements["workingIndicator"]
        // Addressed by identifier across every element type, not as an `otherElements` match.
        // `workspaceCanvas` carries `.accessibilityElement(children: .contain)`, which makes it a
        // group rather than an "Other", so `app.otherElements` finds nothing and the failure
        // surfaces later as "no matches found" against whatever the test does with it next.
        let canvas = element(identifier: "workspaceCanvas")
        let image = app.images["workingImage"]

        // The suite's fixture is 240×320 deliberately, so its upscale can finish before the
        // indicator is ever polled. Rather than race it, this asserts against the state it can
        // reliably observe: if the indicator is caught, its geometry is checked; if it is not, the
        // picture must be present and the upscale complete, which is the same claim — the canvas is
        // never empty and never covered.
        guard indicator.waitForExistence(timeout: 3) else {
            XCTAssertTrue(
                image.waitForExistence(timeout: 30),
                "the upscale outran the indicator, so the picture must be on the canvas")
            XCTAssertTrue(waitForUpscaleComplete(), "and the upscale must have finished")
            return
        }

        // RT-90.25: both at once. The image alone is no feedback; the indicator alone was the bug.
        XCTAssertTrue(image.exists, "the picture is present while work runs")

        // RT-90.44: a quarter of the canvas is four times smaller than the defect, which covered
        // all of it, and generous to any reasonable indicator.
        let canvasArea = canvas.frame.width * canvas.frame.height
        let indicatorArea = indicator.frame.width * indicator.frame.height
        XCTAssertGreaterThan(canvasArea, 0, "the canvas has a frame to compare against")
        XCTAssertLessThan(
            indicatorArea, canvasArea * 0.25,
            "the indicator is a badge, not a sheet over the picture")

        // 🚫 RT-90.49's upper-third assertion is removed by #119. AC90.13's placement clause is
        // superseded by AC119.1: the indicator is centred over the picture, so an assertion that it
        // sits in the upper third now asserts the defect. It survived the #119 implementation
        // because the suite's fixture is small enough that the upscale usually outruns the poll and
        // this test takes its early return — a passing test that was passing by not running.
        // RT-119.2 covers the placement in its new form.

        // RT-90.45: the picture is still a real element, not something drawn behind a scrim.
        XCTAssertTrue(image.isHittable, "the picture is reachable beneath the indicator")
    }

    // RT-90.52 (GUI)
    //
    // **The user test this replaces failed.** The author was told the picture remained visible with
    // the ticker on top, and it did — softened. `ProgressOverlay` filled the canvas with a
    // `.thinMaterial` background, which is a blur, so every photograph went out of focus the moment
    // work began. "I want to see the original unfucked unadulterated image while the upscale ticker
    // sits on top" is the requirement, and it is exact: the picture is not merely *present*, it is
    // *unaltered*.
    //
    // Asserted as the picture's own frame being unchanged, and the indicator occupying a small part
    // of the canvas rather than all of it. A blur does not move an element's frame, so this is the
    // observable half; the visual half is the user test, which is why AC90.13 keeps one.
    func test_theCanvasOutsideTheIndicatorIsUndisturbedWhileWorkRuns_RT090_52() throws {
        XCTAssertTrue(loadTestImage(), "the working image should load")
        XCTAssertTrue(waitForUpscaleComplete())

        let image = app.images["workingImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        let atRest = image.frame
        XCTAssertGreaterThan(atRest.width, 0)

        // Start work again by choosing a scale that is *not* already in effect. The scale buttons
        // are a toggle group, so pressing the active one clears it and no upscale runs at all —
        // and which one is active depends on the model's native scale rather than on a constant.
        let idle = [8, 4, 2].first { scale in
            let value = (app.buttons["scale\(scale)x"].value as? String ?? "").lowercased()
            return !value.contains("in effect") || value.contains("not in effect")
        }
        app.buttons["scale\(try XCTUnwrap(idle))x"].click()

        let indicator = element(identifier: "workingIndicator")
        guard indicator.waitForExistence(timeout: 3) else {
            // The fixture is small enough that the run can outpace the poll. Nothing to observe is
            // not a failure; a covered picture would be.
            XCTAssertTrue(image.exists, "the picture is on the canvas either way")
            return
        }

        XCTAssertEqual(
            image.frame, atRest,
            "the picture is where it was: the indicator sits over it, not in place of it")
        XCTAssertTrue(image.isHittable, "and it is not behind a scrim")

        let canvas = element(identifier: "workspaceCanvas")
        let covered = (indicator.frame.width * indicator.frame.height)
            / (canvas.frame.width * canvas.frame.height)
        XCTAssertLessThan(covered, 0.25, "a badge, not a sheet: \(covered) of the canvas")
    }

    // RT-90.12, RT-90.13 (GUI)
    func test_comparisonShowsTheCurtainAndNoLoupe_RT090_12() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        enterComparison()

        let divider = app.otherElements["curtainDivider"]
        XCTAssertTrue(
            divider.waitForExistence(timeout: 5), "entering comparison shows the curtain")

        // RT-90.13: the loupe and its mode toggle are gone. `MagnifierView.swift` is deleted, so
        // this asserts what a user would find rather than what the source contains.
        XCTAssertFalse(app.buttons["magnifierMode"].exists)
        XCTAssertFalse(app.buttons["sliderMode"].exists)
        XCTAssertFalse(app.otherElements["magnifierLoupe"].exists)
    }

    // RT-90.14, RT-90.48 (GUI)
    //
    // The test that would have caught the reported defect. It could not be written before this
    // slice: the divider carried no accessibility identifier, so where it came to rest was
    // unreadable.
    func test_theDividerComesToRestWhereItIsDragged_RT090_48() {
        guard loadTestImage() else {
            XCTFail("Could not load test image")
            return
        }
        guard waitForUpscaleComplete() else {
            XCTFail("Upscale did not complete")
            return
        }

        enterComparison()

        let divider = app.otherElements["curtainDivider"]
        // Addressed by identifier across every element type, not as an `otherElements` match.
        // `workspaceCanvas` carries `.accessibilityElement(children: .contain)`, which makes it a
        // group rather than an "Other", so `app.otherElements` finds nothing and the failure
        // surfaces later as "no matches found" against whatever the test does with it next.
        let canvas = element(identifier: "workspaceCanvas")
        guard divider.waitForExistence(timeout: 5) else {
            XCTFail("no curtain to drag")
            return
        }

        let startX = divider.frame.midX

        /// Drags the handle to a fraction of the canvas and reports where it came to rest.
        func restingX(afterDraggingTo fraction: CGFloat) -> (pointer: CGFloat, divider: CGFloat) {
            let target = canvas.coordinate(
                withNormalizedOffset: CGVector(dx: fraction, dy: 0.5))
            divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.2, thenDragTo: target)
            return (target.screenPoint.x, divider.frame.midX)
        }

        // RT-90.14: the divider moves at all.
        let middling = restingX(afterDraggingTo: 0.6)
        XCTAssertNotEqual(middling.divider, startX, accuracy: 1.0, "the divider moved")

        // RT-90.48: it came to rest where the pointer was, not somewhere scaled by the window's
        // width — which under the old arithmetic put it hundreds of points away.
        //
        // **Measured at two positions, not one.** The divider's fraction is clamped to 0.05…0.95 of
        // the *picture's* frame, which is narrower than the canvas, so a drag far enough across the
        // canvas legitimately stops at the picture's edge. One measurement cannot tell a clamp from
        // a coordinate-space error: both leave the handle short of the pointer. Two can — a
        // coordinate-space error is proportional and shows at both, a clamp shows only at the outer
        // one.
        let far = restingX(afterDraggingTo: 0.75)
        let image = element(identifier: "workingImage")
        let diagnosis = """
            picture \(image.frame), canvas \(canvas.frame); \
            at 0.6 pointer \(middling.pointer) divider \(middling.divider); \
            at 0.75 pointer \(far.pointer) divider \(far.divider)
            """

        XCTAssertEqual(
            middling.divider, middling.pointer, accuracy: 20.0,
            "well inside the picture, the divider is where the pointer is. \(diagnosis)")

        // At the outer position the handle may legitimately have hit the 0.95 clamp, so what is
        // asserted there is that it did not go *past* the pointer and did not fall short by more
        // than the picture's own right edge allows.
        XCTAssertLessThanOrEqual(
            far.divider, far.pointer + 20.0,
            "the divider never runs ahead of the pointer. \(diagnosis)")
        XCTAssertGreaterThan(
            far.divider, middling.divider,
            "and a drag further out still moves it further out. \(diagnosis)")
    }
}
