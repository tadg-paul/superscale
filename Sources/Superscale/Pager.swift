// ABOUTME: Pager invocation for terminal help output.
// ABOUTME: Delegates terminal detection and pager resolution to an inline shell script via C system().

import CSystemShim
import Foundation

enum Pager {

    /// Display text, using a pager if in an interactive terminal.
    ///
    /// All pager logic (terminal detection, MANPAGER/PAGER resolution,
    /// less -R flag) is handled by an inline shell script invoked via
    /// Darwin.system(). Swift's Process API cannot properly connect a
    /// child process to the controlling terminal, which causes
    /// interactive pagers like less to hang.
    static func display(_ text: String) {
        let tmpPath = NSTemporaryDirectory()
            + "superscale-help-\(ProcessInfo.processInfo.processIdentifier)"

        guard FileManager.default.createFile(
            atPath: tmpPath, contents: text.data(using: .utf8)
        ) else {
            print(text)
            return
        }

        // Shell script handles terminal detection, pager resolution,
        // ANSI passthrough, display, and temp file cleanup.
        // Darwin.system() (C system()) properly inherits the controlling
        // terminal — the same mechanism used by git and man.
        let script = """
            tmpfile='\(tmpPath)'
            if [ -t 1 ] && [ -t 0 ]; then
                pager="${MANPAGER:-${PAGER:-less}}"
                case "$pager" in
                    less|*/less|"less "*)
                        case "${LESS:-}" in *R*) ;; *) pager="$pager -R" ;; esac
                        ;;
                esac
                $pager "$tmpfile"
            else
                cat "$tmpfile"
            fi
            rm -f "$tmpfile"
            """

        _ = c_system(script)
    }
}
