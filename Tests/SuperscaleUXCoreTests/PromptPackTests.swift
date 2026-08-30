// ABOUTME: Verifies that filters describe themselves in frontmatter and that bad ones are reported.
// ABOUTME: Reads the bundled corpus through the real loader and needs no files of its own.

import XCTest
@testable import SuperscaleUXCore

final class PromptPackTests: XCTestCase {
    private let model = "xai/grok-imagine-image"

    // MARK: - Metadata comes from the file, not from its name

    // RT-74.1, RT-74.2 (rewritten for AC85.1: the mechanism is frontmatter, not derivation)
    func test_bundledFiltersLoadWithDeclaredMetadataAndOneCompatibleModel_RT074_1() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        let architectural = try XCTUnwrap(catalogue.pack(id: "image-design-architectural-drawing"))

        // 108 since #138 added the twenty-two the author named. Asserted here as well as in
        // RT-138.1 because this test's other claims are about one specific filter, and a corpus
        // that silently lost entries would still satisfy them.
        XCTAssertEqual(catalogue.packs.count, 108)
        XCTAssertEqual(architectural.displayName, "Architectural Drawing")
        XCTAssertEqual(architectural.category, "Design")
        XCTAssertTrue(architectural.body.hasPrefix("Transform the input image into an architectural drawing."))
        XCTAssertEqual(architectural.compatibleModelIDs, [model])
        XCTAssertEqual(catalogue.packs.map(\.id), catalogue.packs.map(\.id).sorted())
    }

    // RT-85.1
    func test_aFiltersNameAndCategoryAreThoseItsFrontmatterDeclares_RT085_1() throws {
        let packs = try load([
            source("image-lighting-anything", id: "image-lighting-anything", name: "Chiaroscuro", category: "Lighting")
        ])

        XCTAssertEqual(packs.map(\.displayName), ["Chiaroscuro"])
        XCTAssertEqual(packs.map(\.category), ["Lighting"])
    }

    // RT-85.2
    //
    // The filename says one thing and the frontmatter another. A loader that read frontmatter
    // and fell back to the filename would pass RT-85.1; only disagreement separates them.
    func test_aFilterWhoseFrontmatterDisagreesWithItsFilenamePresentsTheFrontmatter_RT085_2() throws {
        let packs = try load([
            source(
                "image-lighting-chiaoscurod",
                id: "image-lighting-chiaoscurod",
                name: "Chiaroscuro",
                category: "Lighting"
            )
        ])

        XCTAssertEqual(packs.first?.displayName, "Chiaroscuro")
        XCTAssertNotEqual(packs.first?.displayName, "Chiaoscurod")
    }

    // RT-85.3
    func test_everyBundledFilterLoadsWithANameAndACategory_RT085_3() throws {
        for pack in try PromptPackCatalogue.bundled().packs {
            XCTAssertFalse(pack.displayName.trimmingCharacters(in: .whitespaces).isEmpty, pack.id)
            XCTAssertFalse(pack.category.trimmingCharacters(in: .whitespaces).isEmpty, pack.id)
        }
    }

    // MARK: - A file that cannot describe itself fails the corpus

    // RT-85.4
    func test_aFileWithNoFrontmatterIsReportedNamingTheFile_RT085_4() {
        assertLoadFails(
            [PromptPackSource(resourceName: "image-design-bare", text: "Just a body, no metadata.")],
            naming: ["image-design-bare", "frontmatter"]
        )
    }

    // RT-85.5
    func test_aFileWhoseFrontmatterIsMalformedOrWronglyTypedIsReportedNamingTheFile_RT085_5() {
        assertLoadFails(
            [PromptPackSource(resourceName: "image-design-broken", text: "---\n{ not json\n---\n\nBody.\n")],
            naming: ["image-design-broken", "malformed"]
        )
        assertLoadFails(
            [PromptPackSource(
                resourceName: "image-design-mistyped",
                text: """
                ---
                {"id": "image-design-mistyped", "name": 42, "category": "Design", "requiresInput": true}
                ---

                Body.
                """
            )],
            naming: ["image-design-mistyped", "malformed"]
        )
        assertLoadFails(
            [PromptPackSource(
                resourceName: "image-design-unterminated",
                text: "---\n{\"id\": \"image-design-unterminated\"}\n\nBody with no closing delimiter.\n"
            )],
            naming: ["image-design-unterminated", "frontmatter"]
        )
    }

    // RT-85.6
    func test_aFileWhoseFrontmatterOmitsARequiredFieldIsReportedNamingTheField_RT085_6() {
        let fields = ["id", "name", "category", "requiresInput"]
        for omitted in fields {
            var values: [String: String] = [
                "id": "\"image-design-partial\"",
                "name": "\"Partial\"",
                "category": "\"Design\"",
                "requiresInput": "true",
            ]
            values.removeValue(forKey: omitted)
            let json = values.map { "\"\($0.key)\": \($0.value)" }.joined(separator: ", ")

            assertLoadFails(
                [PromptPackSource(
                    resourceName: "image-design-partial",
                    text: "---\n{\(json)}\n---\n\nBody.\n"
                )],
                // Quoted, because "invalid" contains "id": an unquoted match would let a
                // report that named no field at all pass for the field most likely to be missing.
                naming: ["image-design-partial", "'\(omitted)'"]
            )
        }
    }

    // RT-85.7
    func test_aFileWhoseBodyIsEmptyAfterItsFrontmatterIsReported_RT085_7() {
        assertLoadFails(
            [source("image-design-hollow", id: "image-design-hollow", body: "   \n\n")],
            naming: ["image-design-hollow", "body"]
        )
    }

    // RT-85.26
    //
    // The one a decoder cannot catch: "" decodes into a String perfectly well, and yields a
    // filter with a blank row in the list.
    func test_aRequiredFieldPresentButEmptyIsReportedNamingTheField_RT085_26() {
        assertLoadFails(
            [source("image-design-blank", id: "image-design-blank", name: "")],
            naming: ["image-design-blank", "'name'"]
        )
        assertLoadFails(
            [source("image-design-spaces", id: "image-design-spaces", category: "   ")],
            naming: ["image-design-spaces", "'category'"]
        )
    }

    // RT-85.20
    func test_aCorpusWithTwoFiltersDeclaringTheSameIdentifierIsReported_RT085_20() {
        assertLoadFails(
            [
                source("image-design-first", id: "image-design-same"),
                source("image-design-second", id: "image-design-same"),
            ],
            naming: ["duplicate", "image-design-same"]
        )
    }

    // RT-85.21
    func test_theBundledCorpusContainsNoDuplicateIdentifier_RT085_21() throws {
        let ids = try PromptPackCatalogue.bundled().packs.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // RT-74.3, RT-74.4 (rewritten against sources; the model check keeps its subject because the
    // loader still supplies compatibleModelIDs and still validates them)
    func test_theLoaderRejectsAnUnsupportedModelAndKeepsBodiesOutOfDiagnostics_RT074_3() {
        let secret = "private prompt wording that must not enter diagnostics"
        let loader = PromptPackLoader(supportedModelIDs: ["some/other-model"])

        do {
            _ = try loader.load(sources: [source("image-design-future", id: "image-design-future", body: secret)])
            XCTFail("Expected an unsupported model to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("image-design-future"))
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("unsupported model"))
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
    }

    // MARK: - The body is what is sent, carried verbatim

    // RT-85.8
    func test_noLoadedFiltersTextContainsAFrontmatterDelimiter_RT085_8() throws {
        for pack in try PromptPackCatalogue.bundled().packs {
            XCTAssertFalse(pack.body.hasPrefix("---"), pack.id)
            XCTAssertFalse(pack.body.contains("\"requiresInput\""), pack.id)
        }
    }

    // RT-85.9
    func test_noBundledFiltersTextBeginsWithAMarkdownHeading_RT085_9() throws {
        for pack in try PromptPackCatalogue.bundled().packs {
            XCTAssertFalse(pack.body.hasPrefix("#"), pack.id)
        }
    }

    // RT-85.10
    //
    // The resource name as a contiguous string, not the words it contains: a file called
    // image-print-risograph has every reason to say "risograph" in its body.
    func test_noFiltersTextContainsItsResourceName_RT085_10() throws {
        for pack in try PromptPackCatalogue.bundled().packs {
            XCTAssertFalse(pack.body.contains(pack.id), pack.id)
            XCTAssertFalse(pack.body.contains("\(pack.id).md"), pack.id)
        }
    }

    // RT-85.11
    func test_theThreeFiltersThatCarriedAFilenameHeadingLoadWithoutIt_RT085_11() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        let offenders = [
            "image-lighting-film-noir",
            "image-lighting-vermeer-window",
            "image-lighting-chiaoscurod",
        ]

        for id in offenders {
            let pack = try XCTUnwrap(catalogue.pack(id: id), id)
            XCTAssertFalse(pack.body.hasPrefix("#"), id)
            XCTAssertFalse(pack.body.contains(id), id)
        }
    }

    // RT-85.24
    //
    // `---` is also a markdown horizontal rule. A parser splitting on every occurrence rather
    // than on the first two would truncate the body silently, which nobody notices because a
    // shortened prompt still produces an image.
    func test_aFilterWhoseBodyContainsAHorizontalRuleLoadsWithThatBodyIntact_RT085_24() throws {
        let body = "First instruction.\n\n---\n\nSecond instruction."
        let packs = try load([source("image-design-ruled", id: "image-design-ruled", body: body)])

        XCTAssertEqual(packs.first?.body, body)
    }

    // RT-85.32
    //
    // The loader does not edit bodies. Without this, a loader that discarded a leading heading
    // would satisfy RT-85.9 to RT-85.11 while the three offending files stayed as they were,
    // and the first filter that legitimately opened with a heading would be truncated.
    func test_aFilterWhoseBodyBeginsWithAHeadingLoadsWithThatHeadingIntact_RT085_32() throws {
        let body = "# Overview\n\nApply the treatment."
        let packs = try load([source("image-design-headed", id: "image-design-headed", body: body)])

        XCTAssertEqual(packs.first?.body, body)
    }

    // MARK: - Identifiers

    // RT-85.19
    //
    // A prettier identifier on one file among 86 would lose that filter's saved default with
    // no error and no message.
    func test_everyBundledIdentifierMatchesTheResourceNameThePreviousVersionDerived_RT085_19() throws {
        for pack in try PromptPackCatalogue.bundled().packs {
            let components = pack.id.split(separator: "-")
            XCTAssertEqual(components.first.map(String.init), "image", pack.id)
            XCTAssertGreaterThanOrEqual(components.count, 3, pack.id)
            XCTAssertNotNil(
                pack.id.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression),
                pack.id
            )
        }
    }

    // MARK: - Fixtures

    private func load(_ sources: [PromptPackSource]) throws -> [PromptPack] {
        try PromptPackLoader(supportedModelIDs: [model]).load(sources: sources)
    }

    private func source(
        _ resourceName: String,
        id: String,
        name: String = "Example",
        category: String = "Design",
        requiresInput: Bool = true,
        body: String = "Apply the bundled treatment."
    ) -> PromptPackSource {
        PromptPackSource(
            resourceName: resourceName,
            text: """
            ---
            {"id": "\(id)", "name": "\(name)", "category": "\(category)", "requiresInput": \(requiresInput)}
            ---

            \(body)
            """
        )
    }

    private func assertLoadFails(
        _ sources: [PromptPackSource],
        naming fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let packs = try PromptPackLoader(supportedModelIDs: [model]).load(sources: sources)
            XCTFail("Expected loading to fail, got \(packs.count) filters", file: file, line: line)
        } catch {
            for fragment in fragments {
                XCTAssertTrue(
                    error.localizedDescription.localizedCaseInsensitiveContains(fragment),
                    "Expected '\(fragment)' in '\(error.localizedDescription)'",
                    file: file,
                    line: line
                )
            }
        }
    }
}

/// The twenty-two prompts the author named on 2026-08-29, and the corpus they joined (#138).
///
/// Package-level throughout: the corpus is a bundled resource and `PromptPackCatalogue.bundled()`
/// loads it without a window.
extension PromptPackTests {
    /// The identifiers the author listed, verbatim.
    private static let namedAdditions = [
        "image-narrative-archaeological-excavation",
        "image-narrative-folklore-witness-illustration",
        "image-narrative-museum-conservation-view",
        "image-narrative-theatrical-stage-set",
        "image-institutional-infrastructure-maintenance-manual",
        "image-institutional-queue-management",
        "image-institutional-public-information-leaflet",
        "image-narrative-forensic-evidence-board",
        "image-zeitgeist-civic-feasibility-study",
        "image-institutional-compliance-photograph",
        "image-media-long-exposure-memory",
        "image-media-contact-sheet",
        "image-media-thermal-receipt",
        "image-media-photogram",
        "image-material-weathered-public-mural",
        "image-material-ceramic-transferware",
        "image-material-cake-decoration",
        "image-narrative-public-aquarium-exhibit",
        "image-narrative-local-history-museum",
        "image-design-board-game-box",
        "image-narrative-disaster-preparedness-diorama",
        "image-print-petrol-station-postcard",
    ]

    // RT-138.1
    func test_theBundledCorpusHoldsOneHundredAndEight_RT138_1() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        XCTAssertEqual(catalogue.packs.count, 108, "86 existing plus the 22 the author named")
    }

    // RT-138.2
    //
    // **Named individually, not counted.** A count of 108 is satisfied by any twenty-two additions,
    // including twenty-two of the wrong ones — the source directory holds 108 files and only these
    // were asked for.
    func test_everyNamedPromptIsPresentAndLoadable_RT138_2() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        for id in Self.namedAdditions {
            let pack = catalogue.pack(id: id)
            XCTAssertNotNil(pack, "\(id) was named by the author and is not in the corpus")
            XCTAssertFalse(pack?.body.isEmpty ?? true, "\(id) loaded with no prompt text")
        }
    }

    // RT-138.3 and RT-138.4
    //
    // Across **all** 108, not only the new ones: a mistyped identifier in a header is caught
    // wherever it lands, and the transformation that produced the new files could as easily have
    // damaged an existing one.
    func test_everyBundledPromptDeclaresItselfConsistently_RT138_3_and_RT138_4() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        for pack in catalogue.packs {
            XCTAssertTrue(pack.id.hasPrefix("image-"), "\(pack.id) does not follow the corpus naming")
            XCTAssertFalse(pack.displayName.isEmpty, "\(pack.id) has no name")
            XCTAssertFalse(pack.category.isEmpty, "\(pack.id) has no category")
            XCTAssertTrue(
                pack.requiresInput,
                "\(pack.id) does not require an input image, and every MVP filter transforms one")
            // Not "contains a hyphen" — that was the first version and it failed on
            // "Post-Vaporwave Muted" and "Texture-Forward Analogue Revival", which are proper names
            // with hyphens in them. What distinguishes a filename is that it is unpunctuated
            // lowercase: a name begins with a capital and is not the identifier's tail verbatim.
            // Capitalisation is mechanical and worth asserting: a name begins with a capital and a
            // filename does not.
            let initial = String(pack.displayName.prefix(1))
            XCTAssertEqual(
                initial, initial.uppercased(),
                "\(pack.id) has a name that does not begin as a name: \"\(pack.displayName)\"")

            // 🚫 No assertion that the name "reads as a name rather than a filename". **It is not
            // machine-checkable and two attempts proved it.** The first rejected any hyphen and
            // failed on "Post-Vaporwave Muted", a proper name. The second compared the name against
            // its identifier's tail and failed on "Solarpunk Civic" — which lowercases back to
            // `solarpunk-civic` precisely *because* the corpus follows its naming convention. The
            // check condemned the convention it was meant to enforce.
            //
            // That judgement is **UT-74.1**, where the author reads the list. My own AC audit for
            // #138 said prompt quality is human judgement, and then I tried to automate the
            // judgement next door to it anyway.
        }
        XCTAssertEqual(
            Set(catalogue.packs.map(\.id)).count, catalogue.packs.count,
            "two entries share an identifier")
    }

    // RT-138.5
    func test_theNarrativeAndInstitutionalCategoriesArePresent_RT138_5() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        let categories = Set(catalogue.packs.map(\.category))

        XCTAssertTrue(categories.contains("Narrative"), "the Narrative category is missing")
        XCTAssertTrue(categories.contains("Institutional"), "the Institutional category is missing")
        XCTAssertEqual(catalogue.packs.filter { $0.category == "Narrative" }.count, 8)
        XCTAssertEqual(catalogue.packs.filter { $0.category == "Institutional" }.count, 4)
    }

    // RT-138.6
    //
    // A floor, not a standard. Nothing machine-checkable establishes that a prompt is *good*, and
    // this does not pretend to — that judgement is UT-74.1's and the author's.
    func test_everyBundledPromptHasABody_RT138_6() throws {
        let catalogue = try PromptPackCatalogue.bundled()
        for pack in catalogue.packs {
            XCTAssertGreaterThan(
                pack.body.trimmingCharacters(in: .whitespacesAndNewlines).count, 40,
                "\(pack.id) has little or no prompt text")
        }
    }
}
