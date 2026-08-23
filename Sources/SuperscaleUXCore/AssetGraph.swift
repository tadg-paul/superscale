// ABOUTME: Owns every image the application holds, their lineage, and the rules that lineage obeys.
// ABOUTME: Makes an upscaled asset unusable as further input so a finished image is never destroyed.

import CoreGraphics
import Foundation

/// What an asset is, which determines where it may be used.
///
/// The harm the rules prevent is exceeding the filter model's working resolution, not upscaling
/// as such: `raisedToMinimum` targets that resolution and remains valid filter input, while
/// `upscaled` targets the size the user asked for and is terminal.
public enum AssetRole: String, Codable, Sendable {
    case source
    case raisedToMinimum
    case filtered
    case upscaled
}

/// A handle to an asset the graph holds.
///
/// Its initializer is deliberately not public: a stage input can only be obtained from a graph,
/// so a location chosen for display cannot be submitted for processing.
public struct AssetReference: Hashable, Sendable {
    let id: UUID

    init(id: UUID) {
        self.id = id
    }
}

/// How an asset was produced. Carries no credential material.
public struct Provenance: Codable, Equatable, Sendable {
    public let filterID: String?
    public let modelID: String?
    public let prompt: String?
    public let sessionID: UUID?

    public init(filterID: String?, modelID: String?, prompt: String?, sessionID: UUID?) {
        self.filterID = filterID
        self.modelID = modelID
        self.prompt = prompt
        self.sessionID = sessionID
    }
}

/// The description of a filter application, supplied when its output is recorded.
///
/// `secrets` are removed from the prompt before it is stored, because the prompt is editable by
/// the user and can therefore contain anything they pasted into it.
public struct FilterProvenance: Equatable, Sendable {
    public let filterID: String
    public let modelID: String
    public let prompt: String
    public let sessionID: UUID?
    public let secrets: [String]

    public init(
        filterID: String,
        modelID: String,
        prompt: String,
        sessionID: UUID?,
        secrets: [String] = []
    ) {
        self.filterID = filterID
        self.modelID = modelID
        self.prompt = prompt
        self.sessionID = sessionID
        self.secrets = secrets
    }
}

public struct Asset: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: AssetRole
    public let fileURL: URL
    public let pixelSize: CGSize
    public let parentID: UUID?
    public let provenance: Provenance?
}

public enum AssetGraphStage: Sendable {
    case filter
    case upscale
}

public enum AssetGraphError: LocalizedError, Equatable, Sendable {
    case noWorkingAsset
    case unknownAsset(UUID)
    case upscaledAssetIsNotAStageInput(UUID)
    case noCandidateToLock
    case notAnUpscaledOutput(UUID)

    public var errorDescription: String? {
        switch self {
        case .noWorkingAsset:
            return "There is no image to work on yet."
        case let .unknownAsset(id):
            return "Asset \(id.uuidString) is not held by this graph."
        case let .upscaledAssetIsNotAStageInput(id):
            return """
                Asset \(id.uuidString) is an upscaled output and cannot be processed further. \
                Processing derives from the working asset at model resolution.
                """
        case .noCandidateToLock:
            return "There is no candidate result to lock."
        case let .notAnUpscaledOutput(id):
            return """
                Asset \(id.uuidString) is not an upscaled output. Only an upscaled output can be \
                promoted or released; everything else is the user's image or a locked iteration.
                """
        }
    }
}

/// An upscale's identity and the location it must write to.
///
/// The graph allocates the location so that no two upscales can collide, which is the guarantee
/// the fixed `upscaled.<ext>` path could not provide.
public struct UpscaleAllocation: Equatable, Sendable {
    public let reference: AssetReference
    public let fileURL: URL
}

/// The assets the application holds, the relationships between them, and the rules those
/// relationships obey.
///
/// Correctness is a property of the structure rather than of a developer remembering an ordering:
/// a stage reads what the graph resolves for it, and an upscaled asset is not resolvable as input.
public struct AssetGraph: Sendable {
    /// Where upscaled outputs are written. Only files beneath it are ever removed.
    public let outputDirectory: URL

    private var assets: [UUID: Asset] = [:]
    private var baseID: UUID?
    private var candidateID: UUID?
    /// Which upscaled asset is the current output. Held explicitly rather than derived, because a
    /// run in progress is allocated before it is promoted: between those two moments two upscaled
    /// assets can share a parent, and deriving would have to pick between them arbitrarily.
    private var currentUpscaleID: UUID?

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    /// The last locked result, or the imported image when nothing has been locked.
    public var base: AssetReference? {
        baseID.map(AssetReference.init(id:))
    }

    /// The unlocked result of the most recent filter, if one is present.
    public var candidate: AssetReference? {
        candidateID.map(AssetReference.init(id:))
    }

    /// What the user is looking at: the candidate when one exists, otherwise the base.
    public var workingAsset: AssetReference? {
        candidate ?? base
    }

    /// The locked iterations behind the current base, oldest first.
    public var lockedIterations: [Asset] {
        guard let baseID, let baseAsset = assets[baseID] else { return [] }
        var chain: [Asset] = []
        var cursor = baseAsset.parentID
        while let id = cursor, let asset = assets[id] {
            chain.append(asset)
            cursor = asset.parentID
        }
        return chain.reversed()
    }

    @discardableResult
    public mutating func importSource(fileURL: URL, pixelSize: CGSize) -> AssetReference {
        let asset = Asset(
            id: UUID(),
            role: .source,
            fileURL: fileURL,
            pixelSize: pixelSize,
            parentID: nil,
            provenance: nil
        )
        assets[asset.id] = asset
        baseID = asset.id
        candidateID = nil
        return AssetReference(id: asset.id)
    }

    public func asset(for reference: AssetReference) throws -> Asset {
        guard let asset = assets[reference.id] else {
            throw AssetGraphError.unknownAsset(reference.id)
        }
        return asset
    }

    /// The asset a stage reads.
    ///
    /// A filter reads the base, so results chain only when locked. An upscale reads the working
    /// asset, so it reflects what the user is looking at.
    public func input(for stage: AssetGraphStage) throws -> AssetReference {
        switch stage {
        case .filter:
            guard let base else { throw AssetGraphError.noWorkingAsset }
            return base
        case .upscale:
            guard let workingAsset else { throw AssetGraphError.noWorkingAsset }
            return workingAsset
        }
    }

    /// Rejects a reference the graph does not hold, and one that names an upscaled output.
    public func validateStageInput(_ reference: AssetReference) throws {
        let asset = try asset(for: reference)
        guard asset.role != .upscaled else {
            throw AssetGraphError.upscaledAssetIsNotAStageInput(asset.id)
        }
    }

    @discardableResult
    public mutating func recordFilterOutput(
        of input: AssetReference,
        fileURL: URL,
        pixelSize: CGSize,
        filter: FilterProvenance
    ) throws -> AssetReference {
        try validateStageInput(input)
        let asset = Asset(
            id: UUID(),
            role: .filtered,
            fileURL: fileURL,
            pixelSize: pixelSize,
            parentID: input.id,
            provenance: Provenance(
                filterID: filter.filterID,
                modelID: filter.modelID,
                prompt: Redaction.applied(to: filter.prompt, secrets: filter.secrets),
                sessionID: filter.sessionID
            )
        )
        assets[asset.id] = asset
        candidateID = asset.id
        return AssetReference(id: asset.id)
    }

    /// Allocates an upscale of `input` and releases the output it supersedes.
    ///
    /// The location is derived from the new asset's identity, so it is unique for the life of the
    /// graph and a released location is never reused.
    /// - Parameter promote: whether the new output immediately becomes the current one, releasing
    ///   the output it supersedes. A caller that is about to run work which may not complete
    ///   passes `false` and promotes on success, so a failed run does not destroy the output the
    ///   user already has.
    public mutating func recordUpscale(
        of input: AssetReference,
        pixelSize: CGSize,
        fileExtension: String,
        promote: Bool = true
    ) throws -> UpscaleAllocation {
        try validateStageInput(input)
        let id = UUID()
        let resolvedExtension = fileExtension.isEmpty ? "png" : fileExtension
        let fileURL = outputDirectory
            .appendingPathComponent("upscaled-\(id.uuidString).\(resolvedExtension)")
        if promote {
            try discardUpscales(of: input.id)
        }
        assets[id] = Asset(
            id: id,
            role: .upscaled,
            fileURL: fileURL,
            pixelSize: pixelSize,
            parentID: input.id,
            provenance: nil
        )
        if promote {
            currentUpscaleID = id
        }
        return UpscaleAllocation(reference: AssetReference(id: id), fileURL: fileURL)
    }

    /// Makes an already-recorded upscale the current output, releasing the one it supersedes.
    public mutating func promote(_ reference: AssetReference) throws {
        let asset = try asset(for: reference)
        guard asset.role == .upscaled, let parentID = asset.parentID else {
            throw AssetGraphError.notAnUpscaledOutput(asset.id)
        }
        try discardUpscales(of: parentID, except: asset.id)
        currentUpscaleID = asset.id
    }

    /// Releases an upscaled output the graph holds, removing its file.
    ///
    /// Only an upscaled asset can be released. Everything else is either the user's image or a
    /// locked iteration, neither of which this operation may reach.
    public mutating func release(_ reference: AssetReference) throws {
        let asset = try asset(for: reference)
        guard asset.role == .upscaled else {
            throw AssetGraphError.notAnUpscaledOutput(asset.id)
        }
        try remove(asset)
        if currentUpscaleID == asset.id {
            currentUpscaleID = nil
        }
    }

    /// Adopts the candidate as the base, leaving the previous base reachable behind it.
    ///
    /// A lock never adopts an upscaled asset: the candidate is a filter result at model
    /// resolution, and an upscale is a derivation of it rather than a step in the chain.
    @discardableResult
    public mutating func lock() throws -> AssetReference {
        guard let candidateID else { throw AssetGraphError.noCandidateToLock }
        baseID = candidateID
        self.candidateID = nil
        return AssetReference(id: candidateID)
    }

    /// Whether the asset's file is still on disk. A locked iteration whose file has gone remains
    /// in the chain, because the chain is the record of what was made.
    public func isAvailable(_ reference: AssetReference) throws -> Bool {
        let asset = try asset(for: reference)
        return FileManager.default.fileExists(atPath: asset.fileURL.path)
    }

    /// The upscaled output of the working asset, when one has been produced for it.
    public func currentUpscale() throws -> AssetReference? {
        guard let workingAsset else { throw AssetGraphError.noWorkingAsset }
        // Read from the explicit pointer rather than searched for, because an allocated run that
        // has not yet been promoted also has the working asset as its parent.
        guard let currentUpscaleID,
              let current = assets[currentUpscaleID],
              current.parentID == workingAsset.id
        else {
            return nil
        }
        return AssetReference(id: current.id)
    }

    /// The nearest session in the asset's ancestry, or none when its ancestry holds none.
    ///
    /// Attribution follows lineage rather than timing, so an unrelated operation performed in
    /// between cannot claim the result.
    public func sessionID(associatedWith reference: AssetReference) throws -> UUID? {
        var cursor: UUID? = try asset(for: reference).id
        while let id = cursor, let asset = assets[id] {
            if let sessionID = asset.provenance?.sessionID { return sessionID }
            cursor = asset.parentID
        }
        return nil
    }

    /// Releases the upscaled outputs of `parentID`, which the caller is about to supersede.
    ///
    /// Only assets of role `upscaled` that the graph itself allocated are reachable here. Sources,
    /// imported images, filter results and locked iterations are outside the operation entirely.
    private mutating func discardUpscales(of parentID: UUID, except retained: UUID? = nil) throws {
        let superseded = assets.values.filter {
            $0.role == .upscaled && $0.parentID == parentID && $0.id != retained
        }
        for asset in superseded {
            try remove(asset)
        }
    }

    private mutating func remove(_ asset: Asset) throws {
        if isOwned(asset.fileURL), FileManager.default.fileExists(atPath: asset.fileURL.path) {
            try FileManager.default.removeItem(at: asset.fileURL)
        }
        assets.removeValue(forKey: asset.id)
        if currentUpscaleID == asset.id {
            currentUpscaleID = nil
        }
    }

    /// Whether the location is one this graph allocated.
    ///
    /// Every upscale is written beneath `outputDirectory`, so this is always true today. It is
    /// checked rather than assumed because the consequence of it ever becoming false is a file
    /// removed from somewhere the graph has no business touching.
    ///
    /// Compared as paths rather than as URLs: a file URL carries a directory flag that survives
    /// standardization, so two URLs naming the same directory compare unequal when one was built
    /// without `isDirectory: true`. `path` omits the trailing separator either way.
    private func isOwned(_ fileURL: URL) -> Bool {
        fileURL.standardizedFileURL.deletingLastPathComponent().path
            == outputDirectory.standardizedFileURL.path
    }
}
