// ABOUTME: Pager invocation for terminal help output.
// ABOUTME: Delegates terminal detection, colour selection, and pager resolution to a shell script via C system().

import CSystemShim
import Foundation

enum Pager {

    /// Display help text, using a pager with colour if in an interactive terminal.
    ///
    /// Both coloured and plain versions are written to temp files. A shell
    /// script (via C `system()`) picks the appropriate version: coloured
    /// through a pager for interactive terminals, plain via cat for piped
    /// output or when NO_COLOR is set.
    ///
    /// Swift's Process API cannot properly connect a child to the controlling
    /// terminal, which causes interactive pagers like less to hang. C system()
    /// inherits the terminal — the same mechanism used by git and man.
    static func display(coloured: String, plain: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let colouredPath = NSTemporaryDirectory() + "superscale-help-c-\(pid)"
        let plainPath = NSTemporaryDirectory() + "superscale-help-p-\(pid)"

        guard FileManager.default.createFile(
            atPath: colouredPath, contents: coloured.data(using: .utf8)
        ), FileManager.default.createFile(
            atPath: plainPath, contents: plain.data(using: .utf8)
        ) else {
            print(plain)
            return
        }

        // Shell script handles terminal detection, NO_COLOR, pager
        // resolution, ANSI passthrough, display, and temp file cleanup.
        let script = """
            coloured='\(colouredPath)'
            plain='\(plainPath)'
            if [ -t 1 ] && [ -t 0 ] && [ -z "${NO_COLOR+x}" ]; then
                pager="${MANPAGER:-${PAGER:-less}}"
                case "$pager" in
                    less|*/less|"less "*)
                        pager="$pager -R"
                        ;;
                esac
                $pager "$coloured"
            else
                cat "$plain"
            fi
            rm -f "$coloured" "$plain"
            """

        _ = c_system(script)
    }
}
