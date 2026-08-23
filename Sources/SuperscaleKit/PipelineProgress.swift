// ABOUTME: What the pipeline is doing, as a value rather than as a sentence a caller must parse.
// ABOUTME: Its description is the text the command-line tool prints, and the only formatting of it.

import Foundation

/// A phase of an upscale, with the counts that belong to it.
///
/// The pipeline previously reported progress as prose, and callers recovered the structure by
/// matching prefixes and splitting on spaces — so rewording a message silently broke a face
/// count. The phase and its numbers are the interface; the wording is for the reader.
public enum PipelineProgress: Equatable, Sendable, CustomStringConvertible {
    case loading(fileName: String)
    case inspecting(width: Int, height: Int, scale: Int)
    case split(tiles: Int, tileSize: Int, overlap: Int)
    case tiling(completed: Int, total: Int)
    case stitching(width: Int, height: Int)
    case upscalingAlpha
    case enhancingFaces(count: Int)
    case resizing(width: Int, height: Int)
    case writing(fileName: String)
    case finished(width: Int, height: Int, fileName: String)
    case warning(String)

    /// The text the pipeline used to emit for this phase, unchanged.
    ///
    /// This is what the command-line tool prints, and nothing else in the executable formats a
    /// `PipelineProgress` — that output is an interface a scripted caller reads, so it stays
    /// exactly as it was while everything producing it is rewritten.
    public var description: String {
        switch self {
        case let .loading(fileName):
            return "Loading \(fileName)..."
        case let .inspecting(width, height, scale):
            return "Input: \(width)×\(height), scale: \(scale)×"
        case let .split(tiles, tileSize, overlap):
            return "Split into \(tiles) tile\(tiles == 1 ? "" : "s") "
                + "(tile size: \(tileSize), overlap: \(overlap))"
        case let .tiling(completed, total):
            return "Processing tile \(completed) of \(total)..."
        case let .stitching(width, height):
            return "Stitching output (\(width)×\(height))..."
        case .upscalingAlpha:
            return "Upscaling alpha channel..."
        case let .enhancingFaces(count):
            return "Enhancing \(count) face\(count == 1 ? "" : "s")..."
        case let .resizing(width, height):
            return "Resizing to \(width)×\(height)..."
        case let .writing(fileName):
            return "Writing \(fileName)..."
        case let .finished(width, height, fileName):
            return "Done: \(width)×\(height) → \(fileName)"
        case let .warning(message):
            return message
        }
    }

    /// Identifies the case without its payload.
    ///
    /// Like `description`, this is a `switch` with no `default`: a case added without being
    /// identified here does not compile. That is what makes an exhaustive list unnecessary —
    /// and a hand-maintained one would be the very thing this type exists to stop.
    var kind: String {
        switch self {
        case .loading: return "loading"
        case .inspecting: return "inspecting"
        case .split: return "split"
        case .tiling: return "tiling"
        case .stitching: return "stitching"
        case .upscalingAlpha: return "upscalingAlpha"
        case .enhancingFaces: return "enhancingFaces"
        case .resizing: return "resizing"
        case .writing: return "writing"
        case .finished: return "finished"
        case .warning: return "warning"
        }
    }
}
