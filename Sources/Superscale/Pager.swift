// ABOUTME: Pager selection and invocation for terminal help output.
// ABOUTME: Resolves pager from MANPAGER/PAGER/less, pipes text through it when in a terminal.

import Foundation

enum Pager {

    /// Display text, using a pager if in an interactive terminal.
    static func display(_ text: String) {
        guard shouldUsePager() else {
            print(text)
            return
        }

        guard let pagerCommand = resolvePager() else {
            print(text)
            return
        }

        pipeThroughPager(text, command: pagerCommand)
    }

    /// Whether the pager should be invoked: stdout is a terminal, stdin is
    /// interactive, and we are not in a subshell (redirected stdout).
    static func shouldUsePager() -> Bool {
        isatty(fileno(stdout)) != 0 && isatty(fileno(stdin)) != 0
    }

    /// Resolve the pager command following shell conventions:
    /// MANPAGER → PAGER → less (in PATH) → nil.
    static func resolvePager() -> String? {
        let env = ProcessInfo.processInfo.environment

        if let manpager = env["MANPAGER"], !manpager.isEmpty {
            return manpager
        }

        if let pager = env["PAGER"], !pager.isEmpty {
            return pager
        }

        // Check if less is available in PATH via shell
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/bin/sh")
        check.arguments = ["-c", "command -v less >/dev/null 2>&1"]
        check.standardOutput = FileHandle.nullDevice
        check.standardError = FileHandle.nullDevice
        do {
            try check.run()
            check.waitUntilExit()
            if check.terminationStatus == 0 { return "less" }
        } catch {
            // shell failed; no less available
        }

        return nil
    }

    /// Pipe text through the pager using a temp file and shell redirect.
    /// This avoids Process pipe fd inheritance issues — the shell handles
    /// all plumbing, and the pager inherits the terminal directly.
    private static func pipeThroughPager(_ text: String, command: String) {
        // When using less, ensure -R for ANSI colour passthrough
        var pagerCommand = command
        let isLess = command == "less" || command.hasSuffix("/less") || command.hasPrefix("less ")
        if isLess {
            let lessEnv = ProcessInfo.processInfo.environment["LESS"] ?? ""
            if !lessEnv.contains("R") && !command.contains("-R") {
                pagerCommand += " -R"
            }
        }

        // Write text to a temp file to avoid pipe buffer issues
        let tmpPath = NSTemporaryDirectory()
            + "superscale-help-\(ProcessInfo.processInfo.processIdentifier)"
        guard FileManager.default.createFile(
            atPath: tmpPath, contents: text.data(using: .utf8)
        ) else {
            print(text)
            return
        }
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        // Shell redirect feeds the file into the pager's stdin
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\(pagerCommand) < '\(tmpPath)'"]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print(text)
        }
    }
}
