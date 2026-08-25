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

    /// The size of the picture that went to the provider.
    ///
    /// Recorded rather than read back from the parent asset, because what is sent is not always the
    /// parent: the memory ceiling reduces a picture before it goes, and the minimum-resolution floor
    /// raises one. A view deriving "did the shape change" from the parent's size would be answering
    /// a question about the graph while appearing to answer one about the provider.
    ///
    /// Optional so that records written before #96 still decode.
    public let sentSize: CGSize?
    /// The size of the picture that came back.
    public let returnedSize: CGSize?

    public init(
        filterID: String?,
        modelID: String?,
        prompt: String?,
        sessionID: UUID?,
        sentSize: CGSize? = nil,
        returnedSize: CGSize? = nil
    ) {
        self.filterID = filterID
        self.modelID = modelID
        self.prompt = prompt
        self.sessionID = sessionID
        self.sentSize = sentSize
        self.returnedSize = returnedSize
    }

    /// Whether the provider returned a different shape from the one it was given.
    ///
    /// Grok raises a short edge under 1024 to the model's working size and squares the result, so a
    /// 3:4 photograph comes back 1:1. A user who sees a square result from a portrait original
    /// should not have to work out whether the application or the provider did it.
    ///
    /// Compared as a ratio with a tolerance, not as equality: a provider rounding to an even number
    /// of pixels changes the ratio in the fourth decimal place and has not reshaped anything.
    /// `nil` where either size is unrecorded — an honest "not known", never a silent "no".
    public var providerChangedTheShape: Bool? {
        guard let sentSize, let returnedSize,
            sentSize.width > 0, sentSize.height > 0,
            returnedSize.width > 0, returnedSize.height > 0
        else {
            return nil
        }
        let sent = sentSize.width / sentSize.height
        let returned = returnedSize.width / returnedSize.height
        return abs(sent - returned) > 0.01 * sent
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
    /// The size of the picture actually submitted, where the caller knows it.
    ///
    /// Only the caller does: it is the one that reduced or raised the picture before uploading it.
    public let sentSize: CGSize?

    public init(
        filterID: String,
        modelID: String,
        prompt: String,
        sessionID: UUID?,
        secrets: [String] = [],
        sentSize: CGSize? = nil
    ) {
        self.filterID = filterID
        self.modelID = modelID
        self.prompt = prompt
        self.sessionID = sessionID
        self.secrets = secrets
        self.sentSize = sentSize
    }
}

public struct Asset: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: AssetRole
    public let fileURL: URL
    public let pixelSize: CGSize
    public let parentID: UUID?
    public let provenance: Provenance?

    /// How to name this asset back to the graph.
    ///
    /// `AssetReference` is deliberately not constructible from outside the package, so that a
    /// caller cannot invent one for a file it happens to know about. An asset the graph has
    /// already handed out is a different matter: it exists, so naming it is safe.
    public var reference: AssetReference {
        AssetReference(id: id)
    }
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

    /// Allocates a raise of `input` to the filterable minimum.
    ///
    /// Distinct from `recordUpscale` in what it produces and what may then be done with it. An
    /// `upscaled` asset targets the size the user asked for and is terminal — the graph refuses it
    /// as a stage input. A `raisedToMinimum` asset targets the *filter model's* working resolution
    /// and is a legitimate filter input, which is the whole reason `AssetRole` distinguishes them.
    ///
    /// On promotion the raised asset becomes the base and any candidate is cleared: a candidate was
    /// made from a picture that is no longer the base, so keeping it would offer a comparison
    /// against something the user is no longer working from. Guide 2.5 describes this as the
    /// sequence the user could have performed by hand — import, upscale to the minimum, lock — and
    /// lock is what moves the base.
    ///
    /// - Parameter promote: whether it becomes the base immediately. A caller about to run work that
    ///   may fail passes `false` and calls `promoteRaise` on success, so a failed raise does not
    ///   leave the base pointing at a file that was never written. Same reasoning as `recordUpscale`.
    @discardableResult
    public mutating func recordRaiseToMinimum(
        of input: AssetReference,
        pixelSize: CGSize,
        fileExtension: String = "png",
        promote: Bool = true
    ) throws -> UpscaleAllocation {
        try validateStageInput(input)
        let id = UUID()
        let resolvedExtension = fileExtension.isEmpty ? "png" : fileExtension
        let fileURL = outputDirectory
            .appendingPathComponent("raised-\(id.uuidString).\(resolvedExtension)")
        assets[id] = Asset(
            id: id,
            role: .raisedToMinimum,
            fileURL: fileURL,
            pixelSize: pixelSize,
            parentID: input.id,
            provenance: nil
        )
        if promote {
            baseID = id
            candidateID = nil
        }
        return UpscaleAllocation(reference: AssetReference(id: id), fileURL: fileURL)
    }

    /// Makes an allocated raise the base, once its pixels exist.
    public mutating func promoteRaise(_ reference: AssetReference) throws {
        let asset = try asset(for: reference)
        guard asset.role == .raisedToMinimum else {
            throw AssetGraphError.notAnUpscaledOutput(asset.id)
        }
        baseID = asset.id
        candidateID = nil
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
                sessionID: filter.sessionID,
                // Where the caller did not say what it sent, the input's own size is the best
                // available answer and is right in every case but a reduced or raised submission.
                sentSize: filter.sentSize ?? assets[input.id]?.pixelSize,
                returnedSize: pixelSize
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
    ///
    /// - Parameter pixelSize: what the stage actually produced. An allocation is made before the
    ///   work runs, so its size is a placeholder until the output exists to be measured.
    public mutating func promote(_ reference: AssetReference, pixelSize: CGSize) throws {
        let asset = try asset(for: reference)
        guard asset.role == .upscaled, let parentID = asset.parentID else {
            throw AssetGraphError.notAnUpscaledOutput(asset.id)
        }
        try discardUpscales(of: parentID, except: asset.id)
        assets[asset.id] = Asset(
            id: asset.id,
            role: asset.role,
            fileURL: asset.fileURL,
            pixelSize: pixelSize,
            parentID: asset.parentID,
            provenance: asset.provenance
        )
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
        return try currentUpscale(of: workingAsset)
    }

    /// The current upscale of a *named* asset.
    ///
    /// The working asset is the candidate when one exists, which is what the user is looking at
    /// unless the filter toggle is showing the base — and then the two disagree. AC89.6 requires the
    /// base's own upscale to be reachable, so the caller that knows which asset is displayed has to
    /// be able to ask about that one. Only `WorkspaceState` knows; the graph holds no toggle.
    public func currentUpscale(of reference: AssetReference) throws -> AssetReference? {
        let asset = try asset(for: reference)
        // Read from the explicit pointer rather than searched for, because an allocated run that
        // has not yet been promoted also has this asset as its parent.
        guard let currentUpscaleID,
              let current = assets[currentUpscaleID],
              current.parentID == asset.id
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
