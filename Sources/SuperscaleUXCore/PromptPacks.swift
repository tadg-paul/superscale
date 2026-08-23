// ABOUTME: Loads and validates the bundled image filters, which describe themselves in frontmatter.
// ABOUTME: Reports a corpus that cannot describe itself rather than guessing metadata from a path.

import FalGenerationKit
import Foundation

public struct PromptPack: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let category: String
    public let body: String
    public let compatibleModelIDs: [String]
    /// Whether the filter transforms an input image rather than producing one from wording alone.
    ///
    /// Nothing reads it yet — every MVP filter transforms. It is declared now so that the version
    /// which generates from a bare prompt is an addition rather than a migration of 86 files.
    public let requiresInput: Bool

    public init(
        id: String,
        displayName: String,
        category: String,
        body: String,
        compatibleModelIDs: [String],
        requiresInput: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.body = body
        self.compatibleModelIDs = compatibleModelIDs
        self.requiresInput = requiresInput
    }
}

/// One filter file as it stands on disk: what it is called, and everything it says.
///
/// The loader takes text rather than locations, which is what keeps the corpus readable from the
/// bundle and testable from a string without either path knowing about the other.
public struct PromptPackSource: Equatable, Sendable {
    public let resourceName: String
    public let text: String

    public init(resourceName: String, text: String) {
        self.resourceName = resourceName
        self.text = text
    }
}

public struct PromptPackLoader: Sendable {
    private static let delimiter = "---"
    private static let compatibleModelIDs = [FalGenerationRequest.defaultModelID]

    private let supportedModelIDs: Set<String>

    public init(supportedModelIDs: Set<String>) {
        self.supportedModelIDs = supportedModelIDs
    }

    /// Reads every filter, or reports the first that cannot describe itself.
    ///
    /// A bad file fails the corpus rather than being skipped: a catalogue quietly short by one is
    /// not something anybody counts, whereas a build that will not start is noticed immediately.
    public func load(sources: [PromptPackSource]) throws -> [PromptPack] {
        var seenIDs = Set<String>()
        var packs: [PromptPack] = []

        for source in sources {
            let pack = try parse(source)
            guard seenIDs.insert(pack.id).inserted else {
                throw PromptPackError.invalidResource(
                    source.resourceName,
                    reason: "duplicate prompt-pack ID '\(pack.id)'"
                )
            }
            packs.append(pack)
        }
        return packs.sorted { $0.id < $1.id }
    }

    private func parse(_ source: PromptPackSource) throws -> PromptPack {
        let (frontmatter, body) = try split(source)
        let metadata = try decode(frontmatter, resourceName: source.resourceName)

        guard !body.isEmpty else {
            throw PromptPackError.invalidResource(source.resourceName, reason: "prompt body is empty")
        }
        try validate(metadata, resourceName: source.resourceName)

        return PromptPack(
            id: metadata.id,
            displayName: metadata.name,
            category: metadata.category,
            body: body,
            compatibleModelIDs: Self.compatibleModelIDs,
            requiresInput: metadata.requiresInput
        )
    }

    /// Splits on the *first two* delimiters only. Everything after the second is body, verbatim:
    /// `---` is also a markdown horizontal rule, and splitting on every occurrence would truncate
    /// such a filter silently, which nobody notices because a shortened prompt still returns an
    /// image.
    private func split(_ source: PromptPackSource) throws -> (frontmatter: String, body: String) {
        var lines = source.text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == Self.delimiter else {
            throw PromptPackError.invalidResource(source.resourceName, reason: "frontmatter is missing")
        }
        lines.removeFirst()

        guard let close = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == Self.delimiter }) else {
            throw PromptPackError.invalidResource(source.resourceName, reason: "frontmatter is not terminated")
        }
        return (
            frontmatter: lines[..<close].joined(separator: "\n"),
            body: lines[lines.index(after: close)...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func decode(_ frontmatter: String, resourceName: String) throws -> PromptPackMetadata {
        do {
            return try JSONDecoder().decode(PromptPackMetadata.self, from: Data(frontmatter.utf8))
        } catch let DecodingError.keyNotFound(key, _) {
            throw PromptPackError.invalidResource(
                resourceName,
                reason: "frontmatter omits required field '\(key.stringValue)'"
            )
        } catch let DecodingError.valueNotFound(_, context) {
            throw PromptPackError.invalidResource(
                resourceName,
                reason: "frontmatter omits required field '\(context.codingPath.last?.stringValue ?? "")'"
            )
        } catch {
            throw PromptPackError.invalidResource(resourceName, reason: "frontmatter is malformed")
        }
    }

    private func validate(_ metadata: PromptPackMetadata, resourceName: String) throws {
        for (field, value) in [("name", metadata.name), ("category", metadata.category)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PromptPackError.invalidResource(
                    resourceName,
                    reason: "frontmatter field '\(field)' is empty"
                )
            }
        }
        guard metadata.id.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
            throw PromptPackError.invalidResource(
                resourceName,
                reason: metadata.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "frontmatter field 'id' is empty"
                    : "frontmatter field 'id' is not an identifier"
            )
        }
        // The model is not file metadata and never was: every filter runs against the one MVP
        // model, which the loader supplies. The check survives because a loader built for an
        // unsupported set must still refuse rather than send.
        guard Set(Self.compatibleModelIDs).isSubset(of: supportedModelIDs) else {
            throw PromptPackError.invalidResource(
                resourceName,
                reason: "metadata references an unsupported model"
            )
        }
    }
}

private struct PromptPackMetadata: Decodable {
    let id: String
    let name: String
    let category: String
    let requiresInput: Bool
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

        let sources = try urls.map { url in
            let resourceName = url.deletingPathExtension().lastPathComponent
            do {
                return PromptPackSource(resourceName: resourceName, text: try String(contentsOf: url, encoding: .utf8))
            } catch {
                throw PromptPackError.invalidResource(resourceName, reason: "resource could not be read")
            }
        }
        let loader = PromptPackLoader(supportedModelIDs: [FalGenerationRequest.defaultModelID])
        return PromptPackCatalogue(packs: try loader.load(sources: sources))
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
