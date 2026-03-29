// ABOUTME: Static help text constants for the CLI.
// ABOUTME: Provides coloured (ANSI) and plain versions of the man-page-style help.

enum HelpText {

    // MARK: - ANSI formatting helpers

    private static func bold(_ text: String) -> String { "\u{1B}[1m\(text)\u{1B}[0m" }
    private static func underline(_ text: String) -> String { "\u{1B}[4m\(text)\u{1B}[0m" }
    private static func boldCyan(_ text: String) -> String { "\u{1B}[1;36m\(text)\u{1B}[0m" }
    private static func green(_ text: String) -> String { "\u{1B}[32m\(text)\u{1B}[0m" }
    private static func yellow(_ text: String) -> String { "\u{1B}[33m\(text)\u{1B}[0m" }

    // MARK: - Coloured (ANSI) help text

    static let coloured: String = {
        let h = boldCyan   // section headings
        let f = green      // flags and commands
        let a = yellow     // arguments and placeholders
        let b = bold
        return """
        \(h("NAME"))
            \(f("superscale")) \u{2014} AI image upscaling for Apple Silicon

        \(h("USAGE"))
            \(f("superscale")) [\(f("-s")) \(a("n"))] [\(f("-o")) \(a("dir"))] [\(f("-m")) \(a("name"))] [\(f("--width")) \(a("px"))] [\(f("--height")) \(a("px"))]
                           [\(f("--stretch"))] [\(f("--tile-size")) \(a("px"))] [\(f("--list-models"))] [\(f("--no-face-enhance"))]
                           [\(f("--download-face-model"))] [\(f("--clear-cache"))] [\(f("--version"))] [\(f("-h"))]
                           \(a("FILE")) [\(a("FILE")) ...]

        \(h("DESCRIPTION"))
            Superscale upscales images using Real-ESRGAN neural networks, running
            natively on your Mac\u{2019}s Neural Engine via CoreML. Images never leave your
            machine. CPU and GPU stay free. A 1024\u{00D7}1024 image upscales 4\u{00D7} in seconds.

            Seven models are bundled, covering photographs, anime/illustration, and
            noisy or compressed sources. The best model is auto-selected based on
            image content using Apple\u{2019}s Vision framework, or you can choose one
            explicitly with \(f("-m")).

        \(h("ARGUMENTS"))
            \(a("FILE"))                Input image file(s). Supports PNG, JPEG, TIFF, HEIC.

        \(h("OPTIONS"))
            \(f("-s, --scale")) \(a("n"))
                Scale factor. Accepts any positive number: integer (2, 4) or
                fractional (2.4, 3.5). Default: 4. Cannot be combined with
                --width/--height.

            \(f("-o, --output")) \(a("dir"))
                Output directory. Created if it does not exist. When omitted,
                output files are written alongside the input.

            \(f("-m, --model")) \(a("name"))
                Model name (see --list-models or MODELS below).
                When omitted, the model is auto-detected from image content.

            \(f("--width")) \(a("px"))
                Target output width in pixels. The image is upscaled at the
                model\u{2019}s native resolution, then resized to fit. When used alone,
                height scales proportionally to preserve aspect ratio.

            \(f("--height")) \(a("px"))
                Target output height in pixels. When used alone, width scales
                proportionally. When both --width and --height are given, the
                image fits within the bounding box preserving aspect ratio.

            \(f("--stretch"))
                Stretch to exact --width and --height, ignoring aspect ratio.
                Requires both --width and --height.

            \(f("--tile-size")) \(a("px"))
                Tile size in pixels for processing. Large images are split into
                overlapping tiles to fit in memory. Smaller tiles use less memory
                but require more inference passes. Default: 512. Reduce if you
                encounter memory pressure on large images.

            \(f("--list-models"))
                List all registered models with their installation status, then
                exit. Shows both bundled upscaling models and the optional face
                enhancement model.

            \(f("--no-face-enhance"))
                Skip face enhancement even when the GFPGAN model is installed.
                By default, face enhancement runs automatically on every upscale
                when the model is present.

            \(f("--download-face-model"))
                Download the optional GFPGAN face enhancement model. Presents
                licence terms (non-commercial) that must be accepted interactively.
                Requires a terminal \u{2014} cannot be run in a script or pipe. Once
                installed, face enhancement runs automatically on every upscale.

            \(f("--clear-cache"))
                Clear the compiled CoreML model cache. Models are compiled from
                .mlpackage to device-optimized .mlmodelc on first use and cached
                in ~/Library/Application Support/superscale/compiled/. This flag
                forces recompilation on the next run.

            \(f("--version"))
                Show version information.

            \(f("-h, --help"))
                Show this help.

        \(h("EXAMPLES"))
            \(f("superscale photo.png"))
                Upscale 4\u{00D7} using auto-detected model. Writes photo_4x.png.

            \(f("superscale -s 2 -o upscaled/ photo.jpg"))
                Upscale 2\u{00D7} to output directory.

            \(f("superscale -s 2.4 photo.png"))
                Fractional scale \u{2014} produces photo_2.4x.png.

            \(f("superscale --width 4096 --height 4096 photo.png"))
                Fit within 4096\u{00D7}4096 bounding box, preserving aspect ratio.

            \(f("superscale --width 1920 --height 1080 --stretch photo.png"))
                Stretch to exact 1920\u{00D7}1080, ignoring aspect ratio.

            \(f("superscale -m realesrgan-anime-6b *.png"))
                Batch process with anime model.

            \(f("superscale -m realesr-general-wdn-x4v3 old_photo.jpg"))
                Denoise and upscale a grainy photo.

        \(h("MODELS"))
            \(f("realesrgan-x4plus"))         4\u{00D7}    General photographs (default)
                Best for general photographs. Balanced sharpening and detail
                preservation. RRDBNet architecture. The default when no model
                is specified and the image is detected as a photograph.

            \(f("realesrgan-x2plus"))         2\u{00D7}    General photographs
                General photographs at 2\u{00D7} scale. Preserves more original detail
                with less hallucination than 4\u{00D7} models. Use when you need a
                lighter upscale or want to stay closer to the source.

            \(f("realesrnet-x4plus"))         4\u{00D7}    PSNR-oriented (less sharpening)
                PSNR-oriented variant \u{2014} less aggressive sharpening, fewer
                artefacts. Preferred for images where fidelity matters more
                than perceived sharpness (e.g. medical, scientific).

            \(f("realesrgan-anime-6b"))       4\u{00D7}    Anime and cel-shaded illustration
                Optimized for anime and cel-shaded illustration. Preserves
                flat colour regions and clean line art. 6-block RRDBNet.

            \(f("realesr-animevideov3"))      4\u{00D7}    Anime video frames
                Compact model designed for anime video frame consistency.
                SRVGGNetCompact architecture \u{2014} faster inference, suitable for
                batch processing of animation frames.

            \(f("realesr-general-x4v3"))      4\u{00D7}    General scenes (fast)
                General scenes with SRVGGNetCompact \u{2014} faster and lighter than
                x4plus. Good when speed matters more than maximum quality.

            \(f("realesr-general-wdn-x4v3"))  4\u{00D7}    Denoise + upscale (grainy/compressed)
                Denoise variant of general-x4v3. Effective for old photographs,
                grainy scans, and heavily compressed JPEG sources. Reduces noise
                while upscaling.

            \(f("gfpgan-v1.4"))               Face enhancement (optional, non-commercial)

            Use \(f("--list-models")) to see installation status.

        \(h("FACE ENHANCEMENT"))
            Optional GFPGAN face enhancement. Not bundled due to non-commercial
            licence (StyleGAN2 NVIDIA Source Code Licence; DFDNet CC BY-NC-SA 4.0).
            Install with: \(f("superscale --download-face-model"))
            Once installed, runs automatically. Skip with \(f("--no-face-enhance")).
            The licence applies to the model weights, not to output images.

        \(h("REQUIREMENTS"))
            macOS 14 (Sonoma) or later. Apple Silicon (M1\u{2013}M5+).
            No other dependencies \u{2014} everything runs on built-in system frameworks.
            Intel Macs are not supported (no Neural Engine).

        \(h("LICENSE"))
            MIT. Copyright Ta\u{1E0B}g Paul.
            Bundled model weights (Real-ESRGAN): BSD-3-Clause, Copyright Xintao Wang 2021.
            GFPGAN face model: contains components under NVIDIA Source Code
            Licence (non-commercial) and CC BY-NC-SA 4.0. The licence applies
            to the model weights, not to output images.

        \(h("SEE ALSO"))
            Report bugs: https://github.com/tigger04/superscale/issues
        """
    }()

    // MARK: - Plain help text (no ANSI)

    static let plain: String = {
        """
        NAME
            superscale \u{2014} AI image upscaling for Apple Silicon

        USAGE
            superscale [-s n] [-o dir] [-m name] [--width px] [--height px]
                           [--stretch] [--tile-size px] [--list-models] [--no-face-enhance]
                           [--download-face-model] [--clear-cache] [--version] [-h]
                           FILE [FILE ...]

        DESCRIPTION
            Superscale upscales images using Real-ESRGAN neural networks, running
            natively on your Mac\u{2019}s Neural Engine via CoreML. Images never leave your
            machine. CPU and GPU stay free. A 1024\u{00D7}1024 image upscales 4\u{00D7} in seconds.

            Seven models are bundled, covering photographs, anime/illustration, and
            noisy or compressed sources. The best model is auto-selected based on
            image content using Apple\u{2019}s Vision framework, or you can choose one
            explicitly with -m.

        ARGUMENTS
            FILE                Input image file(s). Supports PNG, JPEG, TIFF, HEIC.

        OPTIONS
            -s, --scale n
                Scale factor. Accepts any positive number: integer (2, 4) or
                fractional (2.4, 3.5). Default: 4. Cannot be combined with
                --width/--height.

            -o, --output dir
                Output directory. Created if it does not exist. When omitted,
                output files are written alongside the input.

            -m, --model name
                Model name (see --list-models or MODELS below).
                When omitted, the model is auto-detected from image content.

            --width px
                Target output width in pixels. The image is upscaled at the
                model\u{2019}s native resolution, then resized to fit. When used alone,
                height scales proportionally to preserve aspect ratio.

            --height px
                Target output height in pixels. When used alone, width scales
                proportionally. When both --width and --height are given, the
                image fits within the bounding box preserving aspect ratio.

            --stretch
                Stretch to exact --width and --height, ignoring aspect ratio.
                Requires both --width and --height.

            --tile-size px
                Tile size in pixels for processing. Large images are split into
                overlapping tiles to fit in memory. Smaller tiles use less memory
                but require more inference passes. Default: 512. Reduce if you
                encounter memory pressure on large images.

            --list-models
                List all registered models with their installation status, then
                exit. Shows both bundled upscaling models and the optional face
                enhancement model.

            --no-face-enhance
                Skip face enhancement even when the GFPGAN model is installed.
                By default, face enhancement runs automatically on every upscale
                when the model is present.

            --download-face-model
                Download the optional GFPGAN face enhancement model. Presents
                licence terms (non-commercial) that must be accepted interactively.
                Requires a terminal \u{2014} cannot be run in a script or pipe. Once
                installed, face enhancement runs automatically on every upscale.

            --clear-cache
                Clear the compiled CoreML model cache. Models are compiled from
                .mlpackage to device-optimized .mlmodelc on first use and cached
                in ~/Library/Application Support/superscale/compiled/. This flag
                forces recompilation on the next run.

            --version
                Show version information.

            -h, --help
                Show this help.

        EXAMPLES
            superscale photo.png
                Upscale 4\u{00D7} using auto-detected model. Writes photo_4x.png.

            superscale -s 2 -o upscaled/ photo.jpg
                Upscale 2\u{00D7} to output directory.

            superscale -s 2.4 photo.png
                Fractional scale \u{2014} produces photo_2.4x.png.

            superscale --width 4096 --height 4096 photo.png
                Fit within 4096\u{00D7}4096 bounding box, preserving aspect ratio.

            superscale --width 1920 --height 1080 --stretch photo.png
                Stretch to exact 1920\u{00D7}1080, ignoring aspect ratio.

            superscale -m realesrgan-anime-6b *.png
                Batch process with anime model.

            superscale -m realesr-general-wdn-x4v3 old_photo.jpg
                Denoise and upscale a grainy photo.

        MODELS
            realesrgan-x4plus         4\u{00D7}    General photographs (default)
                Best for general photographs. Balanced sharpening and detail
                preservation. RRDBNet architecture. The default when no model
                is specified and the image is detected as a photograph.

            realesrgan-x2plus         2\u{00D7}    General photographs
                General photographs at 2\u{00D7} scale. Preserves more original detail
                with less hallucination than 4\u{00D7} models. Use when you need a
                lighter upscale or want to stay closer to the source.

            realesrnet-x4plus         4\u{00D7}    PSNR-oriented (less sharpening)
                PSNR-oriented variant \u{2014} less aggressive sharpening, fewer
                artefacts. Preferred for images where fidelity matters more
                than perceived sharpness (e.g. medical, scientific).

            realesrgan-anime-6b       4\u{00D7}    Anime and cel-shaded illustration
                Optimized for anime and cel-shaded illustration. Preserves
                flat colour regions and clean line art. 6-block RRDBNet.

            realesr-animevideov3      4\u{00D7}    Anime video frames
                Compact model designed for anime video frame consistency.
                SRVGGNetCompact architecture \u{2014} faster inference, suitable for
                batch processing of animation frames.

            realesr-general-x4v3      4\u{00D7}    General scenes (fast)
                General scenes with SRVGGNetCompact \u{2014} faster and lighter than
                x4plus. Good when speed matters more than maximum quality.

            realesr-general-wdn-x4v3  4\u{00D7}    Denoise + upscale (grainy/compressed)
                Denoise variant of general-x4v3. Effective for old photographs,
                grainy scans, and heavily compressed JPEG sources. Reduces noise
                while upscaling.

            gfpgan-v1.4               Face enhancement (optional, non-commercial)

            Use --list-models to see installation status.

        FACE ENHANCEMENT
            Optional GFPGAN face enhancement. Not bundled due to non-commercial
            licence (StyleGAN2 NVIDIA Source Code Licence; DFDNet CC BY-NC-SA 4.0).
            Install with: superscale --download-face-model
            Once installed, runs automatically. Skip with --no-face-enhance.
            The licence applies to the model weights, not to output images.

        REQUIREMENTS
            macOS 14 (Sonoma) or later. Apple Silicon (M1\u{2013}M5+).
            No other dependencies \u{2014} everything runs on built-in system frameworks.
            Intel Macs are not supported (no Neural Engine).

        LICENSE
            MIT. Copyright Ta\u{1E0B}g Paul.
            Bundled model weights (Real-ESRGAN): BSD-3-Clause, Copyright Xintao Wang 2021.
            GFPGAN face model: contains components under NVIDIA Source Code
            Licence (non-commercial) and CC BY-NC-SA 4.0. The licence applies
            to the model weights, not to output images.

        SEE ALSO
            Report bugs: https://github.com/tigger04/superscale/issues
        """
    }()
}
