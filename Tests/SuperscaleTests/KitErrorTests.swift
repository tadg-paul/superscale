// ABOUTME: Verifies the kit's failures read as sentences rather than as type names and codes.
// ABOUTME: Covers what the user is shown when an upscale cannot proceed.

import XCTest
@testable import SuperscaleKit

final class KitErrorTests: XCTestCase {

    // RT-83.13
    func test_anUnreadableImageProducesADescriptionNamingTheProblem_RT083_13() {
        let failure = ImageIOError.cannotDecodeImage("/tmp/broken.png")

        let description = failure.localizedDescription

        XCTAssertTrue(
            description.localizedCaseInsensitiveContains("broken.png"),
            "the description should name the file: \(description)"
        )
        XCTAssertFalse(description.isEmpty)
    }

    // RT-83.14
    func test_anAbsentModelProducesADescriptionNamingTheModel_RT083_14() {
        let failure = SuperscaleError.modelNotFound("realesrgan-x4plus")

        let description = failure.localizedDescription

        XCTAssertTrue(
            description.localizedCaseInsensitiveContains("realesrgan-x4plus"),
            "the description should name the model: \(description)"
        )
    }

    // RT-83.15
    //
    // Samples the cases that exist. What generalises it is structural rather than tested: each
    // errorDescription is a switch with no default arm, so a case added without one does not
    // compile. That is the guarantee a test cannot hold, and its absence is how D5 arose.
    func test_noKitFailureDescriptionLeaksATypeNameOrCode_RT083_15() {
        let failures: [any Error] = [
            ImageIOError.cannotReadFile("/tmp/a.png"),
            ImageIOError.cannotDecodeImage("/tmp/a.png"),
            ImageIOError.cannotWriteFile("/tmp/out.png"),
            ImageIOError.unsupportedFormat("tga"),
            ImageIOError.dimensionMismatch("expected 512×512"),
            ImageIOError.contextCreationFailed,
            SuperscaleError.noModelOutput,
            SuperscaleError.modelNotFound("missing-model"),
            FaceEnhancerError.modelNotInstalled,
        ]

        for failure in failures {
            let description = failure.localizedDescription
            XCTAssertFalse(
                description.contains("SuperscaleKit"),
                "leaks a type name: \(description)"
            )
            XCTAssertFalse(
                description.contains("The operation couldn"),
                "falls back to the system's generic wording: \(description)"
            )
            XCTAssertFalse(
                description.localizedCaseInsensitiveContains("error 0"),
                "leaks an error code: \(description)"
            )
        }
    }
}
