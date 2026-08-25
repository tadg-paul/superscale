// ABOUTME: Coordinates GUI generation state and persists downloaded provider output.
// ABOUTME: Exposes one generated-file handoff into the shared local upscale coordinator.

import Combine
import FalGenerationKit
import Foundation

@MainActor
public protocol GenerationServing: Sendable {
    func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage

    /// Puts a reference where the provider can fetch it, and says where that is.
    ///
    /// Behind the same seam as `generate` because it is the same provider and the same credential.
    /// Called directly from the view instead, it reached `rest.fal.ai` from the GUI suite — which
    /// makes the tests depend on a network and on somebody else's uptime, and was caught only
    /// because a filter then produced no candidate to lock.
    func uploadReference(_ data: Data, fileName: String, apiKey: String) async throws -> URL
}

public struct FalGenerationService: GenerationServing {
    private let client: FalGenerationClient
    private let storage: FalStorageClient

    public init(
        client: FalGenerationClient = FalGenerationClient(),
        storage: FalStorageClient = FalStorageClient()
    ) {
        self.client = client
        self.storage = storage
    }

    public func generate(_ request: FalGenerationRequest, apiKey: String) async throws -> FalGeneratedImage {
        try await client.generate(request, apiKey: apiKey)
    }

    public func uploadReference(
        _ data: Data, fileName: String, apiKey: String
    ) async throws -> URL {
        try await storage.upload(data, fileName: fileName, apiKey: apiKey)
    }
}

@MainActor
public final class GenerationReferenceSelection: ObservableObject {
    public static let maximumCount = 3
    @Published public private(set) var urls: [URL] = []

    public init() {}

    public func add(_ url: URL) throws {
        guard urls.count < Self.maximumCount else { throw GenerationReferenceError.maximumExceeded }
        urls.append(url)
    }

    public func remove(_ url: URL) {
        urls.removeAll { $0 == url }
    }

    public func clear() {
        urls = []
    }
}

public enum GenerationReferenceError: LocalizedError, Sendable {
    case maximumExceeded

    public var errorDescription: String? {
        "Generation accepts at most three reference images."
    }
}

public struct GeneratedOutput: Equatable, Sendable {
    public let remoteURL: URL
    public let localURL: URL
    public let contentType: String?
    public let warnings: [FalGenerationWarning]
}

public enum GenerationPhase: Equatable, Sendable, CustomStringConvertible {
    case idle
    case generating
    case succeeded(GeneratedOutput)
    case cancelled
    case failed(String)

    public var description: String {
        switch self {
        case .idle: return "idle"
        case .generating: return "generating"
        case .succeeded: return "succeeded"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        }
    }
}

public struct GeneratedImageStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func store(_ image: FalGeneratedImage) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pathExtension = fileExtension(contentType: image.contentType, remoteURL: image.remoteURL)
        let url = directory.appendingPathComponent("generated-\(UUID().uuidString).\(pathExtension)")
        try image.data.write(to: url, options: .atomic)
        return url
    }

    private func fileExtension(contentType: String?, remoteURL: URL) -> String {
        switch contentType?.lowercased() {
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/heic": return "heic"
        case "image/tiff": return "tiff"
        case "image/png": return "png"
        default:
            return remoteURL.pathExtension.isEmpty ? "png" : remoteURL.pathExtension
        }
    }
}

@MainActor
public final class GenerationCoordinator: ObservableObject {
    @Published public private(set) var phase: GenerationPhase = .idle {
        didSet {
            // Any change of phase changes the output, and a new output has no session recorded
            // for it yet. Clearing here rather than at each entry point is what makes "the
            // identifier belongs to this output" structural: the fault this replaced was an
            // identifier outliving what it described because somewhere forgot to clear it.
            recordedSessionID = nil
        }
    }

    private let service: any GenerationServing
    private let outputStore: GeneratedImageStore
    private var operation: Task<Void, Never>?

    public init(service: any GenerationServing, outputStore: GeneratedImageStore) {
        self.service = service
        self.outputStore = outputStore
    }

    public convenience init(outputDirectory: URL) {
        self.init(service: FalGenerationService(), outputStore: GeneratedImageStore(directory: outputDirectory))
    }

    public var output: GeneratedOutput? {
        guard case let .succeeded(output) = phase else { return nil }
        return output
    }

    /// The generation session recorded for the current output, if one was.
    ///
    /// Held here rather than in the view that records it, because that view is `@State`-backed and
    /// SwiftUI destroys it on a mode change — so a user who generated an image, visited Settings,
    /// came back and sent it to upscale lost the association entirely. The coordinator is a
    /// `@StateObject` on the window's root view and outlives the rebuild.
    ///
    /// This is not attribution by timing. The identifier belongs to *this* output: an input from
    /// anywhere else is not the coordinator's output and carries nothing.
    @Published public private(set) var recordedSessionID: UUID?

    /// Records the session written for the current output.
    public func recordSession(_ id: UUID) {
        recordedSessionID = id
    }

    /// The input to a local upscale of the generated image, carrying the session it belongs to.
    public var upscaleSource: GUIUpscaleSource? {
        output.map {
            GUIUpscaleSource(origin: .generatedFile, url: $0.localURL, sessionID: recordedSessionID)
        }
    }

    public func start(_ request: FalGenerationRequest, apiKey: String) {
        operation?.cancel()
        operation = Task { [weak self] in
            await self?.generate(request, apiKey: apiKey)
        }
    }

    /// Puts a reference where the provider can fetch it.
    ///
    /// Routed through the coordinator's own service rather than constructed at the call site, so a
    /// stubbed provider is stubbed for both halves of the exchange.
    public func uploadReference(
        _ data: Data, fileName: String, apiKey: String
    ) async throws -> URL {
        try await service.uploadReference(data, fileName: fileName, apiKey: apiKey)
    }

    public func generate(_ request: FalGenerationRequest, apiKey: String) async {
        phase = .generating
        do {
            let image = try await service.generate(request, apiKey: apiKey)
            try Task.checkCancellation()
            let localURL = try outputStore.store(image)
            phase = .succeeded(
                GeneratedOutput(
                    remoteURL: image.remoteURL,
                    localURL: localURL,
                    contentType: image.contentType,
                    warnings: image.warnings
                )
            )
        } catch is CancellationError {
            phase = .cancelled
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func cancel() {
        operation?.cancel()
        operation = nil
        phase = .cancelled
    }

    public func reset() {
        operation?.cancel()
        operation = nil
        phase = .idle
    }
}
