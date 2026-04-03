// ABOUTME: Before/after comparison view with magnifier loupe and slider modes.
// ABOUTME: Default magnifier mode shows a split loupe at the cursor; slider mode overlays with a divider.

import SwiftUI

/// Comparison mode for the before/after view.
enum ComparisonMode: String {
    case magnifier
    case slider
}

struct ComparisonView: View {
    let original: NSImage
    let upscaled: NSImage

    @State private var comparisonMode: ComparisonMode = .magnifier

    // Magnifier state
    @State private var mousePosition: CGPoint?
    @State private var cursorHidden = false

    // Slider state
    @State private var dividerPosition: CGFloat = 0.35
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var scrollMonitor: Any?

    private static let loupeDiameter: CGFloat = 200
    private static let loupeMagnification: CGFloat = 4.0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                switch comparisonMode {
                case .magnifier:
                    magnifierContent(size: size)
                case .slider:
                    sliderContent(size: size)
                }

                // Mode toggle (top-left)
                VStack {
                    HStack {
                        modeToggle
                            .padding(12)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        HStack(spacing: 2) {
            Button {
                switchToMode(.magnifier)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 26)
                    .background(
                        comparisonMode == .magnifier
                            ? AnyShapeStyle(Color.accentColor.opacity(0.3))
                            : AnyShapeStyle(Color.clear))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .accessibilityIdentifier("modeMagnifier")

            Button {
                switchToMode(.slider)
            } label: {
                Image(systemName: "slider.horizontal.below.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 26)
                    .background(
                        comparisonMode == .slider
                            ? AnyShapeStyle(Color.accentColor.opacity(0.3))
                            : AnyShapeStyle(Color.clear))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .accessibilityIdentifier("modeSlider")
        }
        .buttonStyle(.bordered)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("comparisonModeToggle")
    }

    private func switchToMode(_ mode: ComparisonMode) {
        if comparisonMode != mode {
            // Clean up current mode state
            if comparisonMode == .magnifier {
                restoreCursor()
            } else {
                removeScrollMonitor()
            }
            comparisonMode = mode
        }
    }

    // MARK: - Magnifier mode

    private func magnifierContent(size: CGSize) -> some View {
        ZStack {
            // Full upscaled image at best-fit
            Image(nsImage: upscaled)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size.width, height: size.height)

            // Loupe overlay at cursor position
            if let pos = mousePosition,
               isMouseOverImage(
                   position: pos, imageSize: upscaled.size, viewSize: size) {
                MagnifierView(
                    original: original,
                    upscaled: upscaled,
                    position: pos,
                    viewSize: size,
                    diameter: Self.loupeDiameter,
                    magnification: Self.loupeMagnification)
                .position(pos)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let overImage = isMouseOverImage(
                    position: location, imageSize: upscaled.size, viewSize: size)
                mousePosition = overImage ? location : nil
                if overImage && !cursorHidden {
                    NSCursor.hide()
                    cursorHidden = true
                } else if !overImage && cursorHidden {
                    NSCursor.unhide()
                    cursorHidden = false
                }
            case .ended:
                mousePosition = nil
                restoreCursor()
            }
        }
        .onDisappear { restoreCursor() }
    }

    private func restoreCursor() {
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
    }

    // MARK: - Slider mode

    private func sliderContent(size: CGSize) -> some View {
        let dividerX = size.width * dividerPosition

        return ZStack {
            // Upscaled image (full background)
            imageLayer(image: upscaled, size: size)

            // Original image (clipped to left of divider) — nearest-neighbour
            imageLayer(image: original, size: size, interpolation: .none)
                .clipShape(HorizontalClip(width: dividerX))

            // Divider line
            dividerOverlay(at: dividerX, height: size.height)

            // Zoom controls (top-right)
            VStack {
                HStack {
                    Spacer()
                    zoomControls
                        .padding(12)
                }
                Spacer()
            }

            // Minimap (bottom-right, only when zoomed in)
            if zoom > 1.0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        minimapView(viewSize: size)
                            .padding(12)
                    }
                }
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(panGesture)
        .gesture(magnificationGesture)
        .onAppear { installScrollMonitor() }
        .onDisappear { removeScrollMonitor() }
        .focusable()
        .onKeyPress(characters: CharacterSet(charactersIn: "=+")) { _ in
            zoom = min(10.0, zoom + 0.5)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "-")) { _ in
            zoom = max(1.0, zoom - 0.5)
            if zoom == 1.0 { offset = .zero; dragStart = .zero }
            return .handled
        }
        .onKeyPress(.upArrow) {
            offset.height += 50; dragStart = offset
            return .handled
        }
        .onKeyPress(.downArrow) {
            offset.height -= 50; dragStart = offset
            return .handled
        }
        .onKeyPress(.leftArrow) {
            offset.width += 50; dragStart = offset
            return .handled
        }
        .onKeyPress(.rightArrow) {
            offset.width -= 50; dragStart = offset
            return .handled
        }
    }

    // MARK: - Slider image layer

    private func imageLayer(
        image: NSImage, size: CGSize,
        interpolation: Image.Interpolation = .high
    ) -> some View {
        Image(nsImage: image)
            .interpolation(interpolation)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(zoom)
            .offset(offset)
            .frame(width: size.width, height: size.height)
    }

    // MARK: - Slider divider

    private func dividerOverlay(at x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: height)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .position(x: x, y: height / 2)

            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.3), radius: 3)
                .overlay(
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                )
                .position(x: x, y: height / 2)
                .gesture(dividerDragGesture)
        }
    }

    // MARK: - Slider zoom controls

    private var zoomControls: some View {
        HStack(spacing: 6) {
            Button {
                zoom = max(1.0, zoom - 0.5)
                if zoom == 1.0 { offset = .zero; dragStart = .zero }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }

            Text("\(Int(zoom * 100))%")
                .font(.system(.body, design: .monospaced).bold())
                .frame(width: 52)

            Button {
                zoom = min(10.0, zoom + 0.5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
        }
        .buttonStyle(.bordered)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("zoomControls")
    }

    // MARK: - Slider minimap

    private static let minimapWidth: CGFloat = 150

    private func minimapView(viewSize: CGSize) -> some View {
        let imgAspect = upscaled.size.width / max(upscaled.size.height, 1)
        let thumbW = Self.minimapWidth
        let thumbH = thumbW / max(imgAspect, 0.1)

        return ZStack(alignment: .topLeading) {
            Image(nsImage: upscaled)
                .resizable()
                .frame(width: thumbW, height: thumbH)

            viewportRect(thumbW: thumbW, thumbH: thumbH, viewSize: viewSize)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 4)
        .gesture(minimapDragGesture(thumbW: thumbW, thumbH: thumbH, viewSize: viewSize))
        .accessibilityIdentifier("minimap")
    }

    private func viewportRect(
        thumbW: CGFloat, thumbH: CGFloat, viewSize: CGSize
    ) -> some View {
        let imgAspect = upscaled.size.width / max(upscaled.size.height, 1)
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        let fitW: CGFloat = imgAspect > viewAspect
            ? viewSize.width : viewSize.height * imgAspect
        let fitH: CGFloat = imgAspect > viewAspect
            ? viewSize.width / imgAspect : viewSize.height

        let vpW = min(1.0, viewSize.width / (fitW * zoom))
        let vpH = min(1.0, viewSize.height / (fitH * zoom))
        let cx = 0.5 - offset.width / (fitW * zoom)
        let cy = 0.5 - offset.height / (fitH * zoom)

        return Rectangle()
            .stroke(Color.white, lineWidth: 1.5)
            .background(Color.white.opacity(0.15))
            .frame(width: max(vpW * thumbW, 4), height: max(vpH * thumbH, 4))
            .position(x: cx * thumbW, y: cy * thumbH)
    }

    private func minimapDragGesture(
        thumbW: CGFloat, thumbH: CGFloat, viewSize: CGSize
    ) -> some Gesture {
        let imgAspect = upscaled.size.width / max(upscaled.size.height, 1)
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        let fitW: CGFloat = imgAspect > viewAspect
            ? viewSize.width : viewSize.height * imgAspect
        let fitH: CGFloat = imgAspect > viewAspect
            ? viewSize.width / imgAspect : viewSize.height

        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                let normX = value.location.x / thumbW
                let normY = value.location.y / thumbH
                offset = CGSize(
                    width: (0.5 - normX) * fitW * zoom,
                    height: (0.5 - normY) * fitH * zoom)
                dragStart = offset
            }
    }

    // MARK: - Slider gestures

    private var dividerDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if let window = NSApp.keyWindow {
                    let viewWidth = window.contentView?.frame.width ?? 600
                    let newPosition = value.location.x / viewWidth
                    dividerPosition = max(0.05, min(0.95, newPosition))
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: dragStart.width + value.translation.width,
                    height: dragStart.height + value.translation.height)
            }
            .onEnded { _ in
                dragStart = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = max(1.0, min(10.0, value.magnification))
            }
    }

    // MARK: - Slider scroll monitor

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            offset = CGSize(
                width: offset.width + event.scrollingDeltaX,
                height: offset.height + event.scrollingDeltaY)
            dragStart = offset
            return event
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }
}

// MARK: - Clip shape

/// Clips to the left portion of the view up to the given width.
struct HorizontalClip: Shape {
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: 0, width: width, height: rect.height))
    }
}
