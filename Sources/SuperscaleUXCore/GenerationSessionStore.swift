// ABOUTME: Stores generation history as app-managed assets with Codable JSON metadata.
// ABOUTME: Redacts supplied secrets and links generated images to later local upscales.

import Foundation

public enum GenerationSessionStatus: String, Codable, CaseIterable, Sendable {
    case generated
    case upscaled
    case failed
    case cancelled
}

public struct GenerationSessionDraft: Equatable, Sendable {
    public let prompt: String
    public let modelID: String
    public let estimatedCost: Double?
    public let referencePaths: [String]
    public let timestamp: Date
    public let status: GenerationSessionStatus
    public let safeDiagnostic: String?

    public init(
        prompt: String,
        modelID: String,
        estimatedCost: Double?,
        referencePaths: [String],
        timestamp: Date,
        status: GenerationSessionStatus,
        safeDiagnostic: String?
    ) {
        self.prompt = prompt
        self.modelID = modelID
        self.estimatedCost = estimatedCost
        self.referencePaths = referencePaths
        self.timestamp = timestamp
        self.status = status
        self.safeDiagnostic = safeDiagnostic
    }
}

public struct GenerationSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let prompt: String
    public let modelID: String
    public let estimatedCost: Double?
    public let referencePaths: [String]
    public let timestamp: Date
    public var status: GenerationSessionStatus
    public let safeDiagnostic: String?
    public let generatedAssetPath: String?
    public var upscaledAssetPath: String?
    public let metadataPath: String

    public var generatedAssetURL: URL? {
        generatedAssetPath.map(URL.init(fileURLWithPath:))
    }

    public var upscaledAssetURL: URL? {
        upscaledAssetPath.map(URL.init(fileURLWithPath:))
    }

    /// The finished image, for display and for saving. Not an input to further processing:
    /// sending an upscale back through the pipeline is what destroyed the original.
    public var preferredAssetURL: URL? {
        upscaledAssetURL ?? generatedAssetURL
    }

    /// The input to further processing: the image the session produced, never an upscale of it.
    public var upscaleSource: GUIUpscaleSource? {
        generatedAssetURL.map { url in
            GUIUpscaleSource(origin: .generatedFile, url: url, sessionID: id)
        }
    }
}

public struct GenerationSessionStore: Sendable {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func record(
        _ draft: GenerationSessionDraft,
        generatedAsset: URL?,
        secrets: [String] = []
    ) throws -> GenerationSessionRecord {
        let id = UUID()
        let directory = rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storedAsset = try generatedAsset.map { source in
            let name = "generated.\(source.pathExtension.isEmpty ? "png" : source.pathExtension)"
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: source, to: destination)
            return destination.path
        }
        let metadataURL = directory.appendingPathComponent("metadata.json")
        let diagnostic = draft.safeDiagnostic.map { Redaction.applied(to: $0, secrets: secrets) }
        let record = GenerationSessionRecord(
            id: id,
            prompt: draft.prompt,
            modelID: draft.modelID,
            estimatedCost: draft.estimatedCost,
            referencePaths: draft.referencePaths,
            timestamp: draft.timestamp,
            status: draft.status,
            safeDiagnostic: diagnostic,
            generatedAssetPath: storedAsset,
            upscaledAssetPath: nil,
            metadataPath: metadataURL.path
        )
        try write(record)
        return record
    }

    public func sessions(matching status: GenerationSessionStatus? = nil) throws -> [GenerationSessionRecord] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return [] }
        let directories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let records = directories.compactMap { directory -> GenerationSessionRecord? in
            let metadata = directory.appendingPathComponent("metadata.json")
            guard let data = try? Data(contentsOf: metadata) else { return nil }
            return try? decoder.decode(GenerationSessionRecord.self, from: data)
        }
        return records
            .filter { status == nil || $0.status == status }
            .sorted { $0.timestamp > $1.timestamp }
    }

    public func associateUpscaledAsset(
        _ source: URL,
        withSessionID sessionID: UUID
    ) throws -> GenerationSessionRecord {
        let pathExtension = source.pathExtension.isEmpty ? "png" : source.pathExtension
        return try associateUpscaledAsset(
            Data(contentsOf: source),
            fileExtension: pathExtension,
            withSessionID: sessionID
        )
    }

    public func associateUpscaledAsset(
        _ data: Data,
        fileExtension: String,
        withSessionID sessionID: UUID
    ) throws -> GenerationSessionRecord {
        guard var record = try sessions().first(where: { $0.id == sessionID }) else {
            throw GenerationSessionStoreError.sessionNotFound(sessionID)
        }
        let directory = URL(fileURLWithPath: record.metadataPath).deletingLastPathComponent()
        // Each upscale occupies a location of its own. The former fixed `upscaled.<ext>` name
        // meant a second upscale of the same session destroyed the first.
        let name = "upscaled-\(UUID().uuidString).\(fileExtension.isEmpty ? "png" : fileExtension)"
        let destination = directory.appendingPathComponent(name)
        try data.write(to: destination, options: .atomic)
        record.upscaledAssetPath = destination.path
        record.status = .upscaled
        try write(record)
        return record
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func write(_ record: GenerationSessionRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: URL(fileURLWithPath: record.metadataPath), options: .atomic)
    }
}

public enum GenerationSessionStoreError: LocalizedError, Sendable {
    case sessionNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case let .sessionNotFound(id):
            return "Generation session \(id.uuidString) was not found."
        }
    }
}
