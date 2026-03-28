// ABOUTME: Verifies that SuperscaleKit exposes all required public types.
// ABOUTME: RT-093: imports SuperscaleKit (not @testable) and references all 12 public types.

import XCTest
import SuperscaleKit

final class SuperscaleKitAPITests: XCTestCase {

    // RT-093: All listed types are accessible as public API (no @testable import).
    func test_superscalekit_exposes_all_public_types_RT093() {
        // Pipeline
        let _: Pipeline.Type = Pipeline.self

        // Image I/O
        let _: ImageLoader.Type = ImageLoader.self
        let _: LoadedImage.Type = LoadedImage.self
        let _: ImageWriter.Type = ImageWriter.self

        // Tiling
        let _: Tiler.Type = Tiler.self
        let _: Tile.Type = Tile.self

        // Inference
        let _: CoreMLInference.Type = CoreMLInference.self

        // Content detection
        let _: ContentDetector.Type = ContentDetector.self

        // Face enhancement
        let _: FaceEnhancer.Type = FaceEnhancer.self
        let _: FaceDetector.Type = FaceDetector.self

        // Model management
        let _: ModelRegistry.Type = ModelRegistry.self
        let _: FaceModelRegistry.Type = FaceModelRegistry.self
        let _: ModelCache.Type = ModelCache.self

        // SSIM
        let _: SSIM.Type = SSIM.self
    }
}
