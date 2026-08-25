// ABOUTME: Persists non-secret generation and upscale defaults in application preferences.
// ABOUTME: Validates output folders and model defaults before changing stored values.

import FalGenerationKit
import Foundation

public struct GenerationPreferences: Equatable, Sendable {
    /// Where output goes when the user has not chosen.
    ///
    /// Resolved through `FileManager` rather than built from the home directory, so it is correct on
    /// a machine where Downloads has been moved. Nil only where the directory cannot be resolved at
    /// all, which on a non-sandboxed Mac means something has gone badly wrong.
    public static var defaultOutputFolder: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    public static let defaults = GenerationPreferences(
        outputFolder: GenerationPreferences.defaultOutputFolder,
        defaultModelID: FalGenerationRequest.defaultModelID,
        defaultUpscaleModelID: "auto",
        defaultPromptPackID: nil
    )

    public let outputFolder: URL?
    public let defaultModelID: String
    public let defaultUpscaleModelID: String
    public let defaultPromptPackID: String?

    public init(
        outputFolder: URL?,
        defaultModelID: String,
        defaultUpscaleModelID: String,
        defaultPromptPackID: String?
    ) {
        self.outputFolder = outputFolder
        self.defaultModelID = defaultModelID
        self.defaultUpscaleModelID = defaultUpscaleModelID
        self.defaultPromptPackID = defaultPromptPackID
    }
}

public final class GenerationPreferencesStore {
    private enum Key {
        static let outputFolder = "v2.generation.outputFolder"
        static let modelID = "v2.generation.modelID"
        static let upscaleModelID = "v2.upscale.modelID"
        static let promptPackID = "v2.generation.promptPackID"

        /// Written by versions before #95 and no longer read.
        ///
        /// Named here rather than forgotten: the cost-confirmation control it backed is removed by
        /// guide section 6, and a key nobody names is a key nobody can clean up.
        static let retiredCostThreshold = "v2.generation.costThreshold"
    }

    private let defaults: UserDefaults
    private let folderValidator: (URL) -> Bool

    public convenience init(defaults: UserDefaults = .standard) {
        self.init(defaults: defaults, folderValidator: GenerationPreferencesStore.defaultFolderValidator)
    }

    public init(defaults: UserDefaults, folderValidator: @escaping (URL) -> Bool) {
        self.defaults = defaults
        self.folderValidator = folderValidator
    }

    public func load() -> GenerationPreferences {
        // A stored folder that has gone — an external disk, a directory the user deleted — falls
        // back rather than leaving the application with nowhere to write and nothing to say.
        let storedFolder = defaults.string(forKey: Key.outputFolder)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .flatMap { folderValidator($0) ? $0 : nil }
        let outputFolder = storedFolder ?? GenerationPreferences.defaultOutputFolder
        return GenerationPreferences(
            outputFolder: outputFolder,
            defaultModelID: defaults.string(forKey: Key.modelID) ?? GenerationPreferences.defaults.defaultModelID,
            defaultUpscaleModelID: defaults.string(forKey: Key.upscaleModelID)
                ?? GenerationPreferences.defaults.defaultUpscaleModelID,
            defaultPromptPackID: defaults.string(forKey: Key.promptPackID)
        )
    }

    public func save(_ preferences: GenerationPreferences) throws {
        if let outputFolder = preferences.outputFolder, !folderValidator(outputFolder) {
            throw GenerationPreferencesError.invalidOutputFolder(outputFolder)
        }
        guard !preferences.defaultModelID.isEmpty, !preferences.defaultUpscaleModelID.isEmpty else {
            throw GenerationPreferencesError.invalidModelDefault
        }

        defaults.set(preferences.outputFolder?.path, forKey: Key.outputFolder)
        defaults.set(preferences.defaultModelID, forKey: Key.modelID)
        defaults.set(preferences.defaultUpscaleModelID, forKey: Key.upscaleModelID)
        defaults.set(preferences.defaultPromptPackID, forKey: Key.promptPackID)
        // The retired key goes when preferences are next written, so a machine that has run an
        // earlier build does not keep a value nothing reads.
        defaults.removeObject(forKey: Key.retiredCostThreshold)
    }

    private static func defaultFolderValidator(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: url.path)
    }
}

public enum GenerationPreferencesError: LocalizedError {
    case invalidOutputFolder(URL)
    case invalidModelDefault

    public var errorDescription: String? {
        switch self {
        case let .invalidOutputFolder(url):
            return "The output folder is unavailable or not writable: \(url.path)"
        case .invalidModelDefault:
            return "Generation and upscale model defaults must be selected."
        }
    }
}
