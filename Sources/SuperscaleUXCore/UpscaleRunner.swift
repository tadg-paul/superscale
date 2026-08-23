// ABOUTME: Decides when a local upscale is due, runs it, and supersedes the one it replaces.
// ABOUTME: A stale run reaches nothing: neither its progress nor its result is observed.

import CoreGraphics
import Foundation

/// Owns the upscale in flight and the decision to start one.
///
/// "The working image changed, so the run in flight is stale" and "the model changed, so a run is
/// due" are the same question asked at different moments. Keeping them together is what stops the
/// selection acquiring several writers that race, which is how it behaved before.
@MainActor
public final class UpscaleRunner: ObservableObject {
    @Published public private(set) var state: StageRunState = .idle
    @Published public private(set) var graph: AssetGraph
    @Published public private(set) var settings: UpscaleRunSettings

    private let stage: any UpscaleStaging
    private var task: Task<Void, Never>?
    /// The run whose progress and result are observed. Anything from another run is ignored.
    private var activeRun: UUID?
    /// Where a superseded run will write when it eventually stops, so its output can be removed
    /// once it has actually been produced.
    private var supersededLocations: [UUID: URL] = [:]

    public init(
        stage: any UpscaleStaging,
        graph: AssetGraph,
        settings: UpscaleRunSettings
    ) {
        self.stage = stage
        self.graph = graph
        self.settings = settings
    }

    public var currentUpscale: AssetReference? {
        (try? graph.currentUpscale()) ?? nil
    }

    // MARK: - Events

    public func importImage(fileURL: URL, pixelSize: CGSize) {
        graph.importSource(fileURL: fileURL, pixelSize: pixelSize)
        startIfDue()
    }

    public func choose(_ choice: ScaleChoice) {
        settings.choose(choice)
        startIfDue()
    }

    public func setModel(named name: String, nativeScale: Int) {
        settings.setModel(named: name, nativeScale: nativeScale)
        startIfDue()
    }

    public func setFaceEnhance(_ enabled: Bool) {
        settings.setFaceEnhance(enabled)
        startIfDue()
    }

    public func setCustomDimensions(width: Int?, height: Int?, stretch: Bool? = nil) {
        settings.setCustomDimensions(width: width, height: height, stretch: stretch)
        startIfDue()
    }

    /// A filter was applied or a candidate locked, so what an upscale would derive from has moved.
    public func workingImageChanged() {
        startIfDue()
    }

    /// Stops the run in flight. Cancelling when nothing is running leaves the state alone rather
    /// than reporting a cancellation that did not happen.
    public func cancel() {
        guard activeRun != nil else { return }
        stopActiveRun()
        state = .cancelled
    }

    // MARK: - Running

    private func startIfDue() {
        guard let options = settings.stageOptions else {
            stopActiveRun()
            releaseCurrentUpscale()
            state = .idle
            return
        }
        guard let working = graph.workingAsset,
              let asset = try? graph.asset(for: working)
        else {
            state = .idle
            return
        }
        stopActiveRun()
        start(options: options, working: working, asset: asset)
    }

    private func start(options: UpscaleStageOptions, working: AssetReference, asset: Asset) {
        let allocation: UpscaleAllocation
        do {
            // Allocated without promoting: a run that does not complete must leave the output the
            // user already has exactly as it was.
            allocation = try graph.recordUpscale(
                of: working,
                pixelSize: asset.pixelSize,
                fileExtension: "png",
                promote: false
            )
        } catch {
            state = .failed(.processingFailed(stage: "upscale", reason: error.localizedDescription))
            return
        }

        let run = allocation.reference.id
        activeRun = run
        state = .running(StageProgress(phase: .loading))

        let input = StageInput(
            reference: working,
            fileURL: asset.fileURL,
            pixelSize: asset.pixelSize
        )
        let location = StageOutputLocation(
            reference: allocation.reference,
            fileURL: allocation.fileURL
        )
        task = execute(run: run, input: input, location: location, options: options)
    }

    /// Runs the stage and reports the outcome, ignoring both if the run is superseded meanwhile.
    private func execute(
        run: UUID,
        input: StageInput,
        location: StageOutputLocation,
        options: UpscaleStageOptions
    ) -> Task<Void, Never> {
        let stage = self.stage
        // One stream per run, consumed in order by one child task. A tiled upscale reports once
        // per tile, and unstructured per-report tasks carry no ordering between them, so the
        // progress line could go backwards.
        let (reports, continuation) = AsyncStream<StageProgress>.makeStream()

        return Task { [weak self] in
            let observer = Task { @MainActor [weak self] in
                for await progress in reports {
                    self?.receive(progress, from: run)
                }
            }
            defer { observer.cancel() }

            do {
                let output = try await stage.run(
                    input: input,
                    output: location,
                    options: options,
                    progress: { continuation.yield($0) }
                )
                continuation.finish()
                await observer.value
                await MainActor.run { self?.complete(run, output: output, at: location.reference) }
            } catch {
                continuation.finish()
                await observer.value
                let outcome = Self.outcome(for: error)
                await MainActor.run {
                    self?.abandon(run, at: location.reference, state: outcome)
                }
            }
        }
    }

    /// The run state an error produces. Cancellation is not a failure, and a failure keeps the
    /// reason it carried rather than collapsing to a flag.
    private static func outcome(for error: Error) -> StageRunState {
        if error is CancellationError { return .cancelled }
        if let failure = error as? StageFailure { return .failed(failure) }
        return .failed(.processingFailed(stage: "upscale", reason: error.localizedDescription))
    }

    private func receive(_ progress: StageProgress, from run: UUID) {
        guard activeRun == run else { return }
        state = .running(progress)
    }

    private func complete(_ run: UUID, output: StageOutput, at reference: AssetReference) {
        guard activeRun == run else {
            unlinkSuperseded(run)
            discard(reference)
            return
        }
        do {
            // The size the stage actually produced, replacing the placeholder the allocation
            // carried before there was an output to measure.
            try graph.promote(reference, pixelSize: output.pixelSize)
            activeRun = nil
            state = .succeeded(reference)
        } catch {
            state = .failed(.processingFailed(stage: "upscale", reason: error.localizedDescription))
        }
    }

    private func abandon(_ run: UUID, at reference: AssetReference, state newState: StageRunState) {
        unlinkSuperseded(run)
        discard(reference)
        guard activeRun == run else { return }
        activeRun = nil
        state = newState
    }

    /// Stops observing the run in flight and releases what it had allocated.
    ///
    /// The task is cancelled as well, though the local pipeline does not yet check for it, so the
    /// work continues until its current call returns. Disconnecting the observation is what stops
    /// the superseded run reaching the user in the meantime.
    private func stopActiveRun() {
        guard let run = activeRun else { return }
        task?.cancel()
        task = nil
        activeRun = nil
        // The location is remembered before the asset goes, because the run itself is still
        // working: the local pipeline does not check for cancellation until a later slice, so it
        // will write to this location after the asset has been released. Without this the file
        // would be left behind with nothing referencing it.
        if let asset = try? graph.asset(for: AssetReference(id: run)) {
            supersededLocations[run] = asset.fileURL
        }
        discard(AssetReference(id: run))
    }

    /// Removes what a superseded run wrote after its asset had already been released.
    private func unlinkSuperseded(_ run: UUID) {
        guard let fileURL = supersededLocations.removeValue(forKey: run),
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            state = .failed(.processingFailed(stage: "release", reason: error.localizedDescription))
        }
    }

    private func releaseCurrentUpscale() {
        guard let current = currentUpscale else { return }
        discard(current)
    }

    /// Releases an allocation the runner no longer needs.
    ///
    /// An asset the graph no longer holds is the state this is asking for, so its absence is
    /// checked rather than caught. A file that cannot be removed is a real fault and is reported.
    private func discard(_ reference: AssetReference) {
        guard (try? graph.asset(for: reference)) != nil else { return }
        do {
            try graph.release(reference)
        } catch {
            state = .failed(.processingFailed(stage: "release", reason: error.localizedDescription))
        }
    }
}
