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
    private var cancelledRuns: Set<UUID> = []

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

    public func isCancelled(_ run: UUID) -> Bool {
        cancelledRuns.contains(run)
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
        let stage = self.stage

        task = Task { [weak self] in
            do {
                let output = try await stage.run(
                    input: input,
                    output: location,
                    options: options,
                    progress: { progress in
                        Task { @MainActor [weak self] in
                            self?.receive(progress, from: run)
                        }
                    }
                )
                await MainActor.run { self?.complete(run, output: output, at: allocation.reference) }
            } catch is CancellationError {
                await MainActor.run { self?.abandon(run, at: allocation.reference, state: .cancelled) }
            } catch let failure as StageFailure {
                await MainActor.run {
                    self?.abandon(run, at: allocation.reference, state: .failed(failure))
                }
            } catch {
                let failure = StageFailure.processingFailed(
                    stage: "upscale",
                    reason: error.localizedDescription
                )
                await MainActor.run {
                    self?.abandon(run, at: allocation.reference, state: .failed(failure))
                }
            }
        }
    }

    private func receive(_ progress: StageProgress, from run: UUID) {
        guard activeRun == run else { return }
        state = .running(progress)
    }

    private func complete(_ run: UUID, output: StageOutput, at reference: AssetReference) {
        guard activeRun == run else {
            discard(reference)
            return
        }
        do {
            try graph.promote(reference)
            activeRun = nil
            state = .succeeded(reference)
        } catch {
            state = .failed(.processingFailed(stage: "upscale", reason: error.localizedDescription))
        }
    }

    private func abandon(_ run: UUID, at reference: AssetReference, state newState: StageRunState) {
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
        cancelledRuns.insert(run)
        task?.cancel()
        task = nil
        activeRun = nil
        discard(AssetReference(id: run))
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
