// ABOUTME: The one place the application decides where it keeps what it produces.
// ABOUTME: Two independent resolutions had drifted, so a test launch redirected only some of them.

import Foundation

/// Where the application keeps what it produces: assets, generated images, and session history.
///
/// One value, resolved once, rather than a location computed wherever a component happens to need
/// one. The application previously resolved its root in two places — the entry point, for the
/// generation coordinator and the session store, and a view's property initialiser, for the
/// workspace's asset graph. A launch given a test root redirected the first and not the second, so
/// a UI test wrote its assets into the user's own application-support directory while believing it
/// was sandboxed.
///
/// That is the same shape as the measurement defect AC100.2 records: two ways of deciding one
/// thing, and nothing able to tell them apart. The correction is the same. Storage policy living
/// here rather than in the application target is what `ARCHITECTURE.md` §"Target Module Boundary"
/// already asks for.
public struct StorageRoots: Equatable, Sendable {
    /// The directory everything else hangs from.
    public let root: URL

    /// Assets the workspace allocates, and the images a generation returns.
    ///
    /// One directory for both, because that is where they land in an ordinary launch today. A
    /// sibling would read as tidier and would quietly move every existing installation's files.
    public var generated: URL {
        root.appendingPathComponent("Generated", isDirectory: true)
    }

    /// Session records, kept for recovery and audit.
    public var history: URL {
        root.appendingPathComponent("History", isDirectory: true)
    }

    public init(root: URL) {
        self.root = root
    }

    /// The root the application uses, given whatever a launch configured.
    ///
    /// - Parameter configuredRoot: a root supplied by the launch, or `nil` for an ordinary one.
    ///   Passed in rather than read from the environment here, so that honouring an environment
    ///   variable stays a decision the application makes in one place and under its own build
    ///   conditions. A resolver that read the environment itself would apply to release builds too.
    /// - Parameter fileManager: the file manager whose application-support directory is used.
    public static func resolved(
        configuredRoot: URL?,
        fileManager: FileManager = .default
    ) -> StorageRoots {
        if let configuredRoot {
            return StorageRoots(root: configuredRoot)
        }
        return applicationSupport(fileManager: fileManager)
    }

    /// The ordinary location: `Superscale` beneath the user's application-support directory.
    ///
    /// Falls back to the temporary directory where application support cannot be resolved, which
    /// is the behaviour this replaced and is preserved deliberately: a sandbox denying the
    /// directory should degrade to somewhere writable rather than fail the launch.
    public static func applicationSupport(fileManager: FileManager = .default) -> StorageRoots {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return StorageRoots(root: base.appendingPathComponent("Superscale", isDirectory: true))
    }
}
