// ABOUTME: Verifies the test-layout guard that keeps one-off tests out of the regression pack.
// ABOUTME: Exercises the guard script against synthetic packages built in temporary directories.

import Foundation
import XCTest

final class TestLayoutGuardTests: XCTestCase {

    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        .appendingPathComponent("superscale-test-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot, FileManager.default.fileExists(atPath: fixtureRoot.path) {
            try FileManager.default.removeItem(at: fixtureRoot)
        }
        try super.tearDownWithError()
    }

    // RT-80.1: the guard halts on a package containing a test bearing a one-off identifier
    func test_guard_rejects_package_containing_one_off_test_RT80_1() throws {
        let listing = """
        FixtureTests.ExampleTests/test_something_RT12_1
        FixtureTests.ExampleTests/test_migration_backfilled_OT78_1
        """

        let result = try runGuard(onListing: listing)

        XCTAssertNotEqual(result.status, 0,
                          "Guard should reject a listing containing a one-off identifier. Output: \(result.output)")
        XCTAssertTrue(result.output.contains("test_migration_backfilled_OT78_1"),
                      "Guard should name the offending test. Output: \(result.output)")
    }

    // RT-80.2: the guard proceeds on a package whose tests bear no one-off identifier
    func test_guard_accepts_package_without_one_off_tests_RT80_2() throws {
        let listing = """
        FixtureTests.ExampleTests/test_something_RT12_1
        FixtureTests.ExampleTests/test_other_thing_RT12_2
        """

        let result = try runGuard(onListing: listing)

        XCTAssertEqual(result.status, 0,
                       "Guard should accept a listing with no one-off identifier. Output: \(result.output)")
    }

    // RT-80.3: the guard proceeds on a name holding the identifier letters without forming one
    func test_guard_accepts_names_resembling_one_off_identifiers_RT80_3() throws {
        let listing = """
        FixtureTests.ExampleTests/test_OTHER_case_RT12_1
        FixtureTests.ExampleTests/test_screenshot_OT_RT12_2
        FixtureTests.ExampleTests/test_rotation_OT99_RT12_3
        """

        let result = try runGuard(onListing: listing)

        XCTAssertEqual(result.status, 0,
                       "Guard should not fire on names that merely resemble an identifier. Output: \(result.output)")
    }

    // MARK: - Helpers

    private struct GuardResult {
        let status: Int32
        let output: String
    }

    /// Run the guard against a captured test listing, bypassing the build.
    private func runGuard(onListing listing: String) throws -> GuardResult {
        let listingURL = fixtureRoot.appendingPathComponent("listing.txt")
        try listing.write(to: listingURL, atomically: true, encoding: .utf8)

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [guardScript.path, "--listing", listingURL.path]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return GuardResult(status: process.terminationStatus,
                           output: String(decoding: data, as: UTF8.self))
    }

    private var guardScript: URL {
        projectRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("check-test-layout.sh")
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SuperscaleTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }
}
