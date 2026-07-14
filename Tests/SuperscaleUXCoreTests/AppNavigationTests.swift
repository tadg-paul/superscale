// ABOUTME: Regression tests for GUI mode navigation outside the SwiftUI app.
// ABOUTME: Covers the default mode and explicit transitions among v2 workspaces.

@testable import SuperscaleUXCore
import XCTest

@MainActor
final class AppNavigationTests: XCTestCase {
    // RT-70.4: UX orchestration state can be exercised without launching the app.
    func test_navigation_service_is_usable_without_swiftui_RT70_4() {
        let navigation = AppNavigation()

        XCTAssertEqual(navigation.selectedMode, .upscale)
    }

    // RT-70.5: Upscale is the default and every v2 mode is selectable.
    func test_navigation_defaults_to_upscale_and_selects_all_modes_RT70_5() {
        let navigation = AppNavigation()

        XCTAssertEqual(navigation.selectedMode, .upscale)

        for mode in [AppMode.generate, .history, .settings, .upscale] {
            navigation.select(mode)
            XCTAssertEqual(navigation.selectedMode, mode)
        }
    }
}
