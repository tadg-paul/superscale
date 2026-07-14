// ABOUTME: Persists non-secret generation and upscale defaults in application preferences.
// ABOUTME: Validates cost thresholds and output folders before changing stored values.

import FalGenerationKit
import Foundation

public struct GenerationPreferences: Equatable, Sendable {
    public static let defaults = GenerationPreferences(
        outputFolder: nil,
        costThreshold: 0.05,
        defaultModelID: FalGenerationRequest.defaultModelID,
        defaultUpscaleModelID: "auto",
        defaultPromptPackID: nil
    )

    public let outputFolder: URL?
    public let costThreshold: Double
    public let defaultModelID: String
    public let defaultUpscaleModelID: String
    public let defaultPromptPackID: String?

    public init(
        outputFolder: URL?,
        costThreshold: Double,
        defaultModelID: String,
        defaultUpscaleModelID: String,
        defaultPromptPackID: String?
    ) {
        self.outputFolder = outputFolder
        self.costThreshold = costThreshold
        self.defaultModelID = defaultModelID
        self.defaultUpscaleModelID = defaultUpscaleModelID
        self.defaultPromptPackID = defaultPromptPackID
    }
}

public final class GenerationPreferencesStore {
    private enum Key {
        static let outputFolder = "v2.generation.outputFolder"
        static let costThreshold = "v2.generation.costThreshold"
        static let modelID = "v2.generation.modelID"
        static let upscaleModelID = "v2.upscale.modelID"
        static let promptPackID = "v2.generation.promptPackID"
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
        let storedThreshold = defaults.object(forKey: Key.costThreshold) as? Double
        let outputFolder = defaults.string(forKey: Key.outputFolder).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        return GenerationPreferences(
            outputFolder: outputFolder,
            costThreshold: storedThreshold ?? GenerationPreferences.defaults.costThreshold,
            defaultModelID: defaults.string(forKey: Key.modelID) ?? GenerationPreferences.defaults.defaultModelID,
            defaultUpscaleModelID: defaults.string(forKey: Key.upscaleModelID)
                ?? GenerationPreferences.defaults.defaultUpscaleModelID,
            defaultPromptPackID: defaults.string(forKey: Key.promptPackID)
        )
    }

    public func save(_ preferences: GenerationPreferences) throws {
        guard preferences.costThreshold.isFinite, preferences.costThreshold >= 0 else {
            throw GenerationPreferencesError.invalidCostThreshold
        }
        if let outputFolder = preferences.outputFolder, !folderValidator(outputFolder) {
            throw GenerationPreferencesError.invalidOutputFolder(outputFolder)
        }
        guard !preferences.defaultModelID.isEmpty, !preferences.defaultUpscaleModelID.isEmpty else {
            throw GenerationPreferencesError.invalidModelDefault
        }

        defaults.set(preferences.outputFolder?.path, forKey: Key.outputFolder)
        defaults.set(preferences.costThreshold, forKey: Key.costThreshold)
        defaults.set(preferences.defaultModelID, forKey: Key.modelID)
        defaults.set(preferences.defaultUpscaleModelID, forKey: Key.upscaleModelID)
        defaults.set(preferences.defaultPromptPackID, forKey: Key.promptPackID)
    }

    private static func defaultFolderValidator(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: url.path)
    }
}

public enum GenerationPreferencesError: LocalizedError {
    case invalidCostThreshold
    case invalidOutputFolder(URL)
    case invalidModelDefault

    public var errorDescription: String? {
        switch self {
        case .invalidCostThreshold:
            return "The cost threshold must be a finite value of zero or more."
        case let .invalidOutputFolder(url):
            return "The output folder is unavailable or not writable: \(url.path)"
        case .invalidModelDefault:
            return "Generation and upscale model defaults must be selected."
        }
    }
}
