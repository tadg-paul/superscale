// ABOUTME: Loads and validates immutable prompt packs bundled with the GUI core.
// ABOUTME: Derives stable metadata from resource names and composes packs with user prompts.

import Combine
import FalGenerationKit
import Foundation

public struct PromptPack: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let category: String
    public let body: String
    public let compatibleModelIDs: [String]

    public init(
        id: String,
        displayName: String,
        category: String,
        body: String,
        compatibleModelIDs: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.body = body
        self.compatibleModelIDs = compatibleModelIDs
    }
}

public struct PromptPackDescriptor: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let category: String
    public let resourceName: String
    public let compatibleModelIDs: [String]

    public init(
        id: String,
        displayName: String,
        category: String,
        resourceName: String,
        compatibleModelIDs: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.resourceName = resourceName
        self.compatibleModelIDs = compatibleModelIDs
    }
}

public struct PromptPackLoader: Sendable {
    private let supportedModelIDs: Set<String>

    public init(supportedModelIDs: Set<String>) {
        self.supportedModelIDs = supportedModelIDs
    }

    public func load(
        descriptors: [PromptPackDescriptor],
        bodyProvider: (String) throws -> String
    ) throws -> [PromptPack] {
        var seenIDs = Set<String>()
        var packs: [PromptPack] = []

        for descriptor in descriptors {
            guard seenIDs.insert(descriptor.id).inserted else {
                throw PromptPackError.invalidResource(
                    descriptor.resourceName,
                    reason: "duplicate prompt-pack ID '\(descriptor.id)'"
                )
            }
            try validate(descriptor)

            let body: String
            do {
                body = try bodyProvider(descriptor.resourceName)
            } catch {
                throw PromptPackError.invalidResource(
                    descriptor.resourceName,
                    reason: "prompt body is missing or unreadable"
                )
            }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PromptPackError.invalidResource(descriptor.resourceName, reason: "prompt body is empty")
            }

            packs.append(
                PromptPack(
                    id: descriptor.id,
                    displayName: descriptor.displayName,
                    category: descriptor.category,
                    body: body,
                    compatibleModelIDs: descriptor.compatibleModelIDs
                )
            )
        }
        return packs.sorted { $0.id < $1.id }
    }

    private func validate(_ descriptor: PromptPackDescriptor) throws {
        let idRange = descriptor.id.range(
            of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#,
            options: .regularExpression
        )
        guard idRange != nil,
              !descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !descriptor.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !descriptor.resourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptPackError.invalidResource(descriptor.resourceName, reason: "prompt-pack metadata is malformed")
        }
        guard !descriptor.compatibleModelIDs.isEmpty,
              Set(descriptor.compatibleModelIDs).isSubset(of: supportedModelIDs) else {
            throw PromptPackError.invalidResource(
                descriptor.resourceName,
                reason: "metadata references an unsupported model"
            )
        }
    }
}

public struct PromptPackCatalogue: Sendable {
    public let packs: [PromptPack]

    public init(packs: [PromptPack]) {
        self.packs = packs
    }

    public func pack(id: String) -> PromptPack? {
        packs.first { $0.id == id }
    }

    public static func bundled() throws -> PromptPackCatalogue {
        guard let bundledURLs = Bundle.module.urls(forResourcesWithExtension: "md", subdirectory: nil) else {
            throw PromptPackError.bundleUnavailable
        }
        let urls = bundledURLs.filter { $0.deletingPathExtension().lastPathComponent.hasPrefix("image-") }
        guard !urls.isEmpty else { throw PromptPackError.bundleUnavailable }

        let resources = Dictionary(uniqueKeysWithValues: urls.map { url in
            (url.deletingPathExtension().lastPathComponent, url)
        })
        let descriptors = try resources.keys.map(descriptor(resourceName:))
        let loader = PromptPackLoader(supportedModelIDs: [FalGenerationRequest.defaultModelID])
        let packs = try loader.load(descriptors: descriptors) { resourceName in
            guard let url = resources[resourceName] else {
                throw PromptPackError.invalidResource(resourceName, reason: "resource was not found")
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return PromptPackCatalogue(packs: packs)
    }

    private static func descriptor(resourceName: String) throws -> PromptPackDescriptor {
        let components = resourceName.split(separator: "-").map(String.init)
        guard components.count >= 3, components[0] == "image" else {
            throw PromptPackError.invalidResource(resourceName, reason: "resource name cannot supply prompt-pack metadata")
        }
        return PromptPackDescriptor(
            id: resourceName,
            displayName: components.dropFirst(2).joined(separator: " ").capitalized,
            category: components[1].capitalized,
            resourceName: resourceName,
            compatibleModelIDs: [FalGenerationRequest.defaultModelID]
        )
    }
}

public enum PromptComposer {
    public static func compose(pack: PromptPack?, userPrompt: String) -> String {
        let packBody = pack?.body.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userBody = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return [packBody, userBody].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

@MainActor
public final class PromptPackSelection: ObservableObject {
    @Published public private(set) var selectedPack: PromptPack?
    public let catalogue: PromptPackCatalogue

    public init(catalogue: PromptPackCatalogue, selectedPackID: String? = nil) {
        self.catalogue = catalogue
        self.selectedPack = selectedPackID.flatMap(catalogue.pack(id:))
    }

    public func select(packID: String?) {
        selectedPack = packID.flatMap(catalogue.pack(id:))
    }
}

public enum PromptPackError: LocalizedError, Sendable {
    case bundleUnavailable
    case invalidResource(String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .bundleUnavailable:
            return "Bundled prompt-pack resources are unavailable."
        case let .invalidResource(resourceName, reason):
            return "Prompt-pack resource '\(resourceName)' is invalid: \(reason)."
        }
    }
}
