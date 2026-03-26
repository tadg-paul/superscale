// ABOUTME: Generates structured, man-page-style help text for the CLI.
// ABOUTME: Supports ANSI colour for terminal display and plain text for piped output.

import Foundation

enum HelpFormatter {

    /// Generate the full help text.
    /// - Parameter useColour: Whether to apply ANSI formatting.
    /// - Returns: The formatted help string.
    static func format(useColour: Bool) -> String {
        var lines: [String] = []

        lines.append(section("NAME", useColour: useColour))
        lines.append("    \(bold("superscale", useColour)) \u{2014} AI image upscaling for Apple Silicon")
        lines.append("")

        lines.append(section("USAGE", useColour: useColour))
        lines.append("    \(bold("superscale", useColour)) [\(bold("-s", useColour)) \(underline("n", useColour))] [\(bold("-o", useColour)) \(underline("dir", useColour))] [\(bold("-m", useColour)) \(underline("name", useColour))] [\(bold("--width", useColour)) \(underline("px", useColour))] [\(bold("--height", useColour)) \(underline("px", useColour))]")
        lines.append("               [\(bold("--stretch", useColour))] [\(bold("--tile-size", useColour)) \(underline("px", useColour))] [\(bold("--list-models", useColour))] [\(bold("--no-face-enhance", useColour))]")
        lines.append("               [\(bold("--download-face-model", useColour))] [\(bold("--clear-cache", useColour))] [\(bold("--version", useColour))] [\(bold("-h", useColour))]")
        lines.append("               \(underline("FILE", useColour)) [\(underline("FILE", useColour)) ...]")
        lines.append("")

        lines.append(section("DESCRIPTION", useColour: useColour))
        lines.append("    Superscale upscales images using Real-ESRGAN neural networks, running")
        lines.append("    natively on your Mac\u{2019}s Neural Engine via CoreML. Images never leave your")
        lines.append("    machine. CPU and GPU stay free. A 1024\u{00D7}1024 image upscales 4\u{00D7} in seconds.")
        lines.append("")
        lines.append("    Seven models are bundled, covering photographs, anime/illustration, and")
        lines.append("    noisy or compressed sources. The best model is auto-selected based on")
        lines.append("    image content using Apple\u{2019}s Vision framework, or you can choose one")
        lines.append("    explicitly with \(bold("-m", useColour)).")
        lines.append("")

        lines.append(section("ARGUMENTS", useColour: useColour))
        lines.append("    \(underline("FILE", useColour))                Input image file(s). Supports PNG, JPEG, TIFF, HEIC.")
        lines.append("")

        appendOptions(&lines, useColour: useColour)
        appendExamples(&lines, useColour: useColour)
        appendInstalledModels(&lines, useColour: useColour)
        appendModelDetails(&lines, useColour: useColour)
        appendFaceEnhancement(&lines, useColour: useColour)
        appendRequirements(&lines, useColour: useColour)
        appendLicense(&lines, useColour: useColour)
        appendSeeAlso(&lines, useColour: useColour)

        return lines.joined(separator: "\n")
    }

    /// Whether ANSI colour should be used, based on terminal and env state.
    static func shouldUseColour() -> Bool {
        guard isatty(fileno(stdout)) != 0 else { return false }

        let env = ProcessInfo.processInfo.environment
        if env["NO_COLOR"] != nil { return false }
        if env["TERM"] == "dumb" { return false }

        return true
    }

    // MARK: - Sections

    private static func appendOptions(_ lines: inout [String], useColour: Bool) {
        lines.append(section("OPTIONS", useColour: useColour))

        appendOption(&lines, flags: "-s, --scale", arg: "n", useColour: useColour, description: [
            "Scale factor. Accepts any positive number: integer (2, 4) or",
            "fractional (2.4, 3.5). Default: 4. Cannot be combined with",
            "--width/--height.",
        ])

        appendOption(&lines, flags: "-o, --output", arg: "dir", useColour: useColour, description: [
            "Output directory. Created if it does not exist. When omitted,",
            "output files are written alongside the input.",
        ])

        appendOption(&lines, flags: "-m, --model", arg: "name", useColour: useColour, description: [
            "Model name (see --list-models or INSTALLED MODELS below).",
            "When omitted, the model is auto-detected from image content.",
        ])

        appendOption(&lines, flags: "--width", arg: "px", useColour: useColour, description: [
            "Target output width in pixels. The image is upscaled at the",
            "model\u{2019}s native resolution, then resized to fit. When used alone,",
            "height scales proportionally to preserve aspect ratio.",
        ])

        appendOption(&lines, flags: "--height", arg: "px", useColour: useColour, description: [
            "Target output height in pixels. When used alone, width scales",
            "proportionally. When both --width and --height are given, the",
            "image fits within the bounding box preserving aspect ratio.",
        ])

        appendOption(&lines, flags: "--stretch", arg: nil, useColour: useColour, description: [
            "Stretch to exact --width and --height, ignoring aspect ratio.",
            "Requires both --width and --height.",
        ])

        appendOption(&lines, flags: "--tile-size", arg: "px", useColour: useColour, description: [
            "Tile size in pixels for processing. Large images are split into",
            "overlapping tiles to fit in memory. Smaller tiles use less memory",
            "but require more inference passes. Default: 512. Reduce if you",
            "encounter memory pressure on large images.",
        ])

        appendOption(&lines, flags: "--list-models", arg: nil, useColour: useColour, description: [
            "List all registered models with their installation status, then",
            "exit. Shows both bundled upscaling models and the optional face",
            "enhancement model.",
        ])

        appendOption(&lines, flags: "--no-face-enhance", arg: nil, useColour: useColour, description: [
            "Skip face enhancement even when the GFPGAN model is installed.",
            "By default, face enhancement runs automatically on every upscale",
            "when the model is present.",
        ])

        appendOption(&lines, flags: "--download-face-model", arg: nil, useColour: useColour, description: [
            "Download the optional GFPGAN face enhancement model. Presents",
            "licence terms (non-commercial) that must be accepted interactively.",
            "Requires a terminal \u{2014} cannot be run in a script or pipe. Once",
            "installed, face enhancement runs automatically on every upscale.",
        ])

        appendOption(&lines, flags: "--clear-cache", arg: nil, useColour: useColour, description: [
            "Clear the compiled CoreML model cache. Models are compiled from",
            ".mlpackage to device-optimized .mlmodelc on first use and cached",
            "in ~/Library/Application Support/superscale/compiled/. This flag",
            "forces recompilation on the next run.",
        ])

        appendOption(&lines, flags: "--version", arg: nil, useColour: useColour, description: [
            "Show version information.",
        ])

        appendOption(&lines, flags: "-h, --help", arg: nil, useColour: useColour, description: [
            "Show this help.",
        ])
    }

    private static func appendOption(
        _ lines: inout [String], flags: String, arg: String?,
        useColour: Bool, description: [String]
    ) {
        if let arg = arg {
            lines.append("    \(bold(flags, useColour)) \(underline(arg, useColour))")
        } else {
            lines.append("    \(bold(flags, useColour))")
        }
        for line in description {
            lines.append("        \(line)")
        }
        lines.append("")
    }

    private static func appendExamples(_ lines: inout [String], useColour: Bool) {
        lines.append(section("EXAMPLES", useColour: useColour))

        let examples: [(command: String, description: String)] = [
            ("superscale photo.png",
             "Upscale 4\u{00D7} using auto-detected model. Writes photo_4x.png."),
            ("superscale -s 2 -o upscaled/ photo.jpg",
             "Upscale 2\u{00D7} to output directory."),
            ("superscale -s 2.4 photo.png",
             "Fractional scale \u{2014} produces photo_2.4x.png."),
            ("superscale --width 4096 --height 4096 photo.png",
             "Fit within 4096\u{00D7}4096 bounding box, preserving aspect ratio."),
            ("superscale --width 1920 --height 1080 --stretch photo.png",
             "Stretch to exact 1920\u{00D7}1080, ignoring aspect ratio."),
            ("superscale -m realesrgan-anime-6b *.png",
             "Batch process with anime model."),
            ("superscale -m realesr-general-wdn-x4v3 old_photo.jpg",
             "Denoise and upscale a grainy photo."),
        ]

        for example in examples {
            lines.append("    \(bold(example.command, useColour))")
            lines.append("        \(example.description)")
            lines.append("")
        }
    }

    private static func appendInstalledModels(_ lines: inout [String], useColour: Bool) {
        lines.append(section("INSTALLED MODELS", useColour: useColour, suffix: " (details below)"))

        for model in ModelRegistry.models {
            let status = ModelRegistry.isInstalled(model) ? "installed" : "not installed"
            let defaultLabel = model.isDefault ? " [default]" : ""
            let nameCol = bold(model.name, useColour)
                .padding(toLength: model.name.count + (useColour ? 8 : 0) + (28 - model.name.count),
                         withPad: " ", startingAt: 0)
            let scaleCol = "\(model.scale)\u{00D7}".padding(toLength: 5, withPad: " ", startingAt: 0)
            let descCol = "\(model.displayName)\(defaultLabel)"
                .padding(toLength: 38, withPad: " ", startingAt: 0)
            lines.append("    \(nameCol)\(scaleCol)\(descCol)\(dim("[\(status)]", useColour))")
        }

        lines.append("")
        lines.append("    Face enhancement:")
        let faceName = "gfpgan-v1.4"
        let faceNameCol = bold(faceName, useColour)
            .padding(toLength: faceName.count + (useColour ? 8 : 0) + (28 - faceName.count),
                     withPad: " ", startingAt: 0)
        let faceDesc = "Face enhancement (optional)"
            .padding(toLength: 43, withPad: " ", startingAt: 0)
        if FaceModelRegistry.isInstalled {
            lines.append("    \(faceNameCol)\(faceDesc)\(dim("[installed]", useColour))")
        } else {
            lines.append("    \(faceNameCol)\(faceDesc)\(dim("[not installed]", useColour))")
            lines.append("    Install with: \(bold("superscale --download-face-model", useColour))")
        }
        lines.append("")
    }

    private static func appendModelDetails(_ lines: inout [String], useColour: Bool) {
        lines.append(section("MODEL DETAILS", useColour: useColour))

        let details: [(name: String, suffix: String, description: [String])] = [
            ("realesrgan-x4plus", " (default)", [
                "Best for general photographs. Balanced sharpening and detail",
                "preservation. RRDBNet architecture. The default when no model",
                "is specified and the image is detected as a photograph.",
            ]),
            ("realesrgan-x2plus", "", [
                "General photographs at 2\u{00D7} scale. Preserves more original detail",
                "with less hallucination than 4\u{00D7} models. Use when you need a",
                "lighter upscale or want to stay closer to the source.",
            ]),
            ("realesrnet-x4plus", "", [
                "PSNR-oriented variant \u{2014} less aggressive sharpening, fewer",
                "artefacts. Preferred for images where fidelity matters more",
                "than perceived sharpness (e.g. medical, scientific).",
            ]),
            ("realesrgan-anime-6b", "", [
                "Optimized for anime and cel-shaded illustration. Preserves",
                "flat colour regions and clean line art. 6-block RRDBNet.",
            ]),
            ("realesr-animevideov3", "", [
                "Compact model designed for anime video frame consistency.",
                "SRVGGNetCompact architecture \u{2014} faster inference, suitable for",
                "batch processing of animation frames.",
            ]),
            ("realesr-general-x4v3", "", [
                "General scenes with SRVGGNetCompact \u{2014} faster and lighter than",
                "x4plus. Good when speed matters more than maximum quality.",
            ]),
            ("realesr-general-wdn-x4v3", "", [
                "Denoise variant of general-x4v3. Effective for old photographs,",
                "grainy scans, and heavily compressed JPEG sources. Reduces noise",
                "while upscaling.",
            ]),
        ]

        for detail in details {
            lines.append("    \(bold(detail.name, useColour))\(detail.suffix)")
            for line in detail.description {
                lines.append("        \(line)")
            }
            lines.append("")
        }
    }

    private static func appendFaceEnhancement(_ lines: inout [String], useColour: Bool) {
        lines.append(section("FACE ENHANCEMENT", useColour: useColour))
        lines.append("    Optional GFPGAN face enhancement. Not bundled due to non-commercial")
        lines.append("    licence (StyleGAN2 NVIDIA Source Code Licence; DFDNet CC BY-NC-SA 4.0).")
        lines.append("    Install with: \(bold("superscale --download-face-model", useColour))")
        lines.append("    Once installed, runs automatically. Skip with \(bold("--no-face-enhance", useColour)).")
        lines.append("    The licence applies to the model weights, not to output images.")
        lines.append("")
    }

    private static func appendRequirements(_ lines: inout [String], useColour: Bool) {
        lines.append(section("REQUIREMENTS", useColour: useColour))
        lines.append("    macOS 14 (Sonoma) or later. Apple Silicon (M1\u{2013}M5+).")
        lines.append("    No other dependencies \u{2014} everything runs on built-in system frameworks.")
        lines.append("    Intel Macs are not supported (no Neural Engine).")
        lines.append("")
    }

    private static func appendLicense(_ lines: inout [String], useColour: Bool) {
        lines.append(section("LICENSE", useColour: useColour))
        lines.append("    MIT. Copyright Ta\u{1E0B}g Paul.")
        lines.append("    Bundled model weights (Real-ESRGAN): BSD-3-Clause, Copyright Xintao Wang 2021.")
        if FaceModelRegistry.isInstalled {
            lines.append("    GFPGAN face model (installed): contains components under NVIDIA Source")
            lines.append("    Code Licence (non-commercial) and CC BY-NC-SA 4.0. The licence applies")
            lines.append("    to the model weights, not to output images.")
        }
        lines.append("")
    }

    private static func appendSeeAlso(_ lines: inout [String], useColour: Bool) {
        lines.append(section("SEE ALSO", useColour: useColour))
        lines.append("    Report bugs: https://github.com/tigger04/superscale/issues")
    }

    // MARK: - ANSI formatting

    private static func section(_ name: String, useColour: Bool, suffix: String = "") -> String {
        "\(bold(name, useColour))\(suffix)"
    }

    private static func bold(_ text: String, _ useColour: Bool) -> String {
        useColour ? "\u{1B}[1m\(text)\u{1B}[0m" : text
    }

    private static func underline(_ text: String, _ useColour: Bool) -> String {
        useColour ? "\u{1B}[4m\(text)\u{1B}[0m" : text
    }

    private static func dim(_ text: String, _ useColour: Bool) -> String {
        useColour ? "\u{1B}[2m\(text)\u{1B}[0m" : text
    }
}
