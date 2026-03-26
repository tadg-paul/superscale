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

        do {
            try pipeThroughPager(text, command: pagerCommand)
        } catch {
            // Fallback to direct output if pager fails
            print(text)
        }
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

        // Check if less is available in PATH
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "less"]
        which.standardOutput = FileHandle.nullDevice
        which.standardError = FileHandle.nullDevice
        do {
            try which.run()
            which.waitUntilExit()
            if which.terminationStatus == 0 {
                return "less"
            }
        } catch {
            // which failed; no less available
        }

        return nil
    }

    /// Pipe text through the resolved pager command.
    private static func pipeThroughPager(_ text: String, command: String) throws {
        // Split command into executable and arguments
        let components = command.components(separatedBy: " ").filter { !$0.isEmpty }
        guard let executable = components.first else {
            print(text)
            return
        }

        var arguments = Array(components.dropFirst())

        // When using less, ensure -R is present for ANSI colour passthrough
        if executable == "less" || executable.hasSuffix("/less") {
            let lessEnv = ProcessInfo.processInfo.environment["LESS"] ?? ""
            if !lessEnv.contains("-R") && !lessEnv.contains("R") && !arguments.contains("-R") {
                arguments.insert("-R", at: 0)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments

        let inputPipe = Pipe()
        process.standardInput = inputPipe

        try process.run()

        if let data = text.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()
    }
}
