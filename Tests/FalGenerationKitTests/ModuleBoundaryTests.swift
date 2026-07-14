// ABOUTME: Compile-time regression test for the FAL generation package boundary.
// ABOUTME: Ensures the GUI-only generation module remains independently testable.

@testable import FalGenerationKit
import XCTest

final class ModuleBoundaryTests: XCTestCase {
    // RT-70.3: Importing this target proves SwiftPM builds it independently.
    func test_fal_generation_module_is_importable_RT70_3() {
        XCTAssertNotNil(FalGenerationBoundary())
    }
}
