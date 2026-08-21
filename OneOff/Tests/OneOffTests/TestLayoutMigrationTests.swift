// ABOUTME: One-off verification of the regression and one-off test package split.
// ABOUTME: Confirms the regression command cannot reach one-off tests after relocation.

import Foundation
import XCTest

final class TestLayoutMigrationTests: XCTestCase {

    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("superscale-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot, FileManager.default.fileExists(atPath: fixtureRoot.path) {
            try FileManager.default.removeItem(at: fixtureRoot)
        }
        try super.tearDownWithError()
    }

    // OT-80.1: the main package's enumerated tests hold nothing from the one-off package
    func test_mainPackageListingExcludesOneOffTests_OT80_1() throws {
        let listing = try listTests(packagePath: projectRoot.path)

        let oneOffNames = listing.filter { $0.contains("OT78_1") || $0.contains("OneOffTests") }

        XCTAssertTrue(oneOffNames.isEmpty,
                      "Main package should hold no one-off tests, found: \(oneOffNames)")
    }

    // OT-80.2: the co-located regression test survived the relocation
    func test_mainPackageListingRetainsCoLocatedRegressionTest_OT80_2() throws {
        let listing = try listTests(packagePath: projectRoot.path)

        XCTAssertTrue(listing.contains { $0.contains("RT78_1") },
                      "RT-78.1 should remain in the regression package")
    }

    // OT-80.3: the one-off package's enumerated tests hold the relocated test
    func test_oneOffPackageListingContainsRelocatedTest_OT80_3() throws {
        let listing = try listTests(packagePath: oneOffPackage.path)

        XCTAssertTrue(listing.contains { $0.contains("OT78_1") },
                      "Relocated one-off test should be present in the one-off package")
    }

    // OT-80.5: a one-off test in a synthetic one-off package is absent from the main listing
    func test_syntheticOneOffTestAbsentFromMainListing_OT80_5() throws {
        let fixture = try makeSyntheticPair(includingOneOffTest: true)

        let listing = try listTests(packagePath: fixture.mainPackage.path)

        XCTAssertFalse(listing.contains { $0.contains("OT99_1") },
                       "A one-off test in the sibling package must not appear in the main listing")
    }

    // OT-80.6: the same synthetic one-off test is present in the one-off listing
    func test_syntheticOneOffTestPresentInOneOffListing_OT80_6() throws {
        let fixture = try makeSyntheticPair(includingOneOffTest: true)

        let listing = try listTests(packagePath: fixture.oneOffPackage.path)

        XCTAssertTrue(listing.contains { $0.contains("OT99_1") },
                      "A one-off test should be reachable in its own package")
    }

    // OT-80.4: the relocated one-off test passes in its new home
    func test_relocatedOneOffTestPassesInNewHome_OT80_4() throws {
        let scratch = fixtureRoot.appendingPathComponent("scratch-relocated", isDirectory: true)
        let result = try run(executable: "/usr/bin/env",
                             arguments: ["swift", "test",
                                         "--package-path", oneOffPackage.path,
                                         "--scratch-path", scratch.path,
                                         "--filter", "OT78_"],
                             workingDirectory: projectRoot)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("OT78_1"),
                      "Expected the relocated test to run. Output: \(result.output)")
    }

    // OT-80.7: no regression test was lost, measured against the pre-relocation baseline
    func test_regressionSuiteRetainsPreRelocationTests_OT80_7() throws {
        let baseline = try loadBaseline()
        let current = Set(try listTests(packagePath: projectRoot.path))

        let relocated = baseline.filter { $0.contains("OT78_1") }
        XCTAssertEqual(relocated.count, 1,
                       "Baseline should contain exactly the one relocated one-off test")

        let expected = baseline.subtracting(relocated)
        let missing = expected.subtracting(current)

        XCTAssertTrue(missing.isEmpty,
                      "Relocation lost regression tests: \(missing.sorted())")
    }

    // OT-80.8: the regression command passes and executes no one-off test
    func test_regressionCommandPassesWithoutOneOffTests_OT80_8() throws {
        let result = try runMake(target: "test", arguments: [])

        XCTAssertEqual(result.status, 0,
                       "Regression command should pass. Output tail: \(tail(result.output))")

        let executedOneOff = result.output
            .split(separator: "\n")
            .filter { $0.contains("Test Case") && $0.contains("_OT") }

        XCTAssertTrue(executedOneOff.isEmpty,
                      "Regression run executed one-off tests: \(executedOneOff)")
    }

    // OT-80.9: an issue filter matching nothing reports the absence
    //
    // `swift test --filter` exits 0 when its pattern matches nothing, so the
    // entry point has to detect that itself. This exercises the entry point.
    func test_oneOffFilterWithNoMatchesReportsAbsence_OT80_9() throws {
        let result = try run(executable: "/bin/bash",
                             arguments: [runOneOffScript.path, "99999"],
                             workingDirectory: projectRoot)

        XCTAssertNotEqual(result.status, 0,
                          "An issue with no one-off tests should report, not pass silently. Output: \(result.output)")
        XCTAssertTrue(result.output.contains("no one-off tests found"),
                      "The absence should be stated plainly. Output: \(result.output)")
    }

    // OT-80.11: an issue filter matching a one-off test selects it
    func test_oneOffFilterSelectsMatchingTest_OT80_11() throws {
        let scratch = fixtureRoot.appendingPathComponent("scratch-filter", isDirectory: true)
        let result = try run(executable: "/usr/bin/env",
                             arguments: ["swift", "test",
                                         "--package-path", oneOffPackage.path,
                                         "--scratch-path", scratch.path,
                                         "--filter", "OT78_"],
                             workingDirectory: projectRoot)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("OT78_1"),
                      "Filtering to issue 78 should select its one-off test. Output: \(result.output)")
    }

    // OT-80.10: the regression command halts on a package holding a misplaced one-off test
    func test_regressionCommandHaltsOnMisplacedOneOffTest_OT80_10() throws {
        let fixture = try makeSyntheticPair(includingOneOffTest: false)
        try addTest(named: "test_misplaced_OT99_1", to: fixture.mainPackage)

        let result = try runMake(target: "test",
                                 arguments: ["GUARD_PACKAGE_PATH=\(fixture.mainPackage.path)"])

        XCTAssertNotEqual(result.status, 0,
                          "Regression command should halt on a misplaced one-off test. Output: \(result.output)")
        XCTAssertTrue(result.output.contains("OT99_1"),
                      "The halt should name the offending test. Output: \(result.output)")
    }

    // OT-80.12: the regression command proceeds past the guard on a clean package
    func test_regressionCommandProceedsOnCleanPackage_OT80_12() throws {
        let fixture = try makeSyntheticPair(includingOneOffTest: false)

        let result = try runGuard(packagePath: fixture.mainPackage.path)

        XCTAssertEqual(result.status, 0,
                       "Guard should pass a clean package. Output: \(result.output)")
    }

    // MARK: - Helpers

    private struct SyntheticPair {
        let mainPackage: URL
        let oneOffPackage: URL
    }

    /// Enumerate a package's tests.
    ///
    /// SwiftPM locks its build directory. Enumerating the package that is
    /// currently running these tests would contend for that lock and deadlock,
    /// so that one case is given its own scratch directory. Other packages have
    /// their own build directories already and reuse them, which keeps this
    /// fast: a fresh scratch path forces a full rebuild every time.
    private func listTests(packagePath: String) throws -> [String] {
        var arguments = ["swift", "test", "--list-tests", "--package-path", packagePath]

        if URL(fileURLWithPath: packagePath).standardizedFileURL == oneOffPackage.standardizedFileURL {
            let scratch = fixtureRoot.appendingPathComponent("scratch", isDirectory: true)
            arguments.append(contentsOf: ["--scratch-path", scratch.path])
        }

        let result = try run(executable: "/usr/bin/env",
                             arguments: arguments,
                             workingDirectory: projectRoot)
        return result.output
            .split(separator: "\n")
            .map(String.init)
    }

    private func runGuard(packagePath: String) throws -> (status: Int32, output: String) {
        try run(executable: "/bin/bash",
                arguments: [projectRoot.appendingPathComponent("scripts/check-test-layout.sh").path,
                            "--package-path", packagePath],
                workingDirectory: projectRoot)
    }

    private func runMake(target: String, arguments: [String]) throws -> (status: Int32, output: String) {
        try run(executable: "/usr/bin/env",
                arguments: ["make", target] + arguments,
                workingDirectory: projectRoot)
    }

    private func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Build a minimal main package and a sibling one-off package in the fixture root.
    private func makeSyntheticPair(includingOneOffTest: Bool) throws -> SyntheticPair {
        let mainPackage = fixtureRoot.appendingPathComponent("Main", isDirectory: true)
        let oneOffPackage = fixtureRoot.appendingPathComponent("OneOff", isDirectory: true)

        try makePackage(at: mainPackage, named: "FixtureMain", testTarget: "FixtureMainTests")
        try addTest(named: "test_ordinary_RT12_1", to: mainPackage)

        try makePackage(at: oneOffPackage, named: "FixtureOneOff", testTarget: "FixtureOneOffTests")
        if includingOneOffTest {
            try addTest(named: "test_synthetic_OT99_1", to: oneOffPackage)
        }

        return SyntheticPair(mainPackage: mainPackage, oneOffPackage: oneOffPackage)
    }

    private func makePackage(at root: URL, named name: String, testTarget: String) throws {
        let testDirectory = root
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent(testTarget, isDirectory: true)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)

        let manifest = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "\(name)",
            platforms: [.macOS(.v14)],
            targets: [
                .testTarget(name: "\(testTarget)", path: "Tests/\(testTarget)"),
            ]
        )
        """
        try manifest.write(to: root.appendingPathComponent("Package.swift"),
                           atomically: true,
                           encoding: .utf8)
    }

    private func addTest(named testName: String, to packageRoot: URL) throws {
        let testsRoot = packageRoot.appendingPathComponent("Tests", isDirectory: true)
        let targets = try FileManager.default.contentsOfDirectory(
            at: testsRoot,
            includingPropertiesForKeys: nil
        )
        guard let target = targets.first else {
            throw SyntheticFixtureError.noTestTarget(packageRoot.path)
        }

        let className = "Generated\(abs(testName.hashValue))Tests"
        let source = """
        import XCTest

        final class \(className): XCTestCase {
            func \(testName)() throws {
                XCTAssertTrue(true)
            }
        }
        """
        try source.write(to: target.appendingPathComponent("\(className).swift"),
                         atomically: true,
                         encoding: .utf8)
    }

    private enum SyntheticFixtureError: Error {
        case noTestTarget(String)
        case baselineMissing(String)
    }

    /// The main package's test names as they stood before relocation, captured
    /// from the commit preceding this change.
    private func loadBaseline() throws -> Set<String> {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("pre-relocation-tests.txt")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SyntheticFixtureError.baselineMissing(url.path)
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        return Set(
            contents
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    private func tail(_ output: String, lines: Int = 20) -> String {
        output.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }

    private var oneOffPackage: URL {
        projectRoot.appendingPathComponent("OneOff", isDirectory: true)
    }

    private var runOneOffScript: URL {
        projectRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("run-one-off.sh")
    }

    /// The repository root, four levels above this file.
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // OneOffTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // OneOff/
            .deletingLastPathComponent()  // repository root
    }
}
