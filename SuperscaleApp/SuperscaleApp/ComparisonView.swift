// ABOUTME: Before/after comparison view with draggable vertical divider.
// ABOUTME: Overlays original and upscaled images with synchronised zoom and pan.

import SwiftUI

struct ComparisonView: View {
    let original: NSImage
    let upscaled: NSImage

    @State private var dividerPosition: CGFloat = 0.35
    @State private var zoom: CGFloat = 1.5
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @GestureState private var isDraggingDivider = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let dividerX = size.width * dividerPosition

            ZStack {
                // Upscaled image (full background)
                imageLayer(image: upscaled, size: size)

                // Original image (clipped to left of divider) — nearest-neighbour so the
                // user sees the actual source pixels, not Apple's interpolated version.
                imageLayer(image: original, size: size, interpolation: .none)
                    .clipShape(
                        HorizontalClip(width: dividerX)
                    )

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
    }

    // MARK: - Image layer

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

    // MARK: - Divider

    private func dividerOverlay(at x: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: height)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .position(x: x, y: height / 2)

            // Handle
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

    // MARK: - Zoom controls

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

    // MARK: - Minimap

    private static let minimapWidth: CGFloat = 150

    private func minimapView(viewSize: CGSize) -> some View {
        let imgAspect = upscaled.size.width / max(upscaled.size.height, 1)
        let thumbW = Self.minimapWidth
        let thumbH = thumbW / max(imgAspect, 0.1)

        return ZStack(alignment: .topLeading) {
            Image(nsImage: upscaled)
                .resizable()
                .frame(width: thumbW, height: thumbH)

            // Viewport indicator rectangle
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
        // Compute the fit size of the image at zoom=1 within the view
        let imgAspect = upscaled.size.width / max(upscaled.size.height, 1)
        let viewAspect = viewSize.width / max(viewSize.height, 1)
        let fitW: CGFloat
        let fitH: CGFloat
        if imgAspect > viewAspect {
            fitW = viewSize.width
            fitH = viewSize.width / imgAspect
        } else {
            fitH = viewSize.height
            fitW = viewSize.height * imgAspect
        }

        // Viewport size in normalised image coords
        let vpW = min(1.0, viewSize.width / (fitW * zoom))
        let vpH = min(1.0, viewSize.height / (fitH * zoom))

        // Viewport centre offset from image centre
        let cx = 0.5 - offset.width / (fitW * zoom)
        let cy = 0.5 - offset.height / (fitH * zoom)

        // Map to minimap pixel coords
        let rectW = vpW * thumbW
        let rectH = vpH * thumbH
        let rectX = cx * thumbW - rectW / 2
        let rectY = cy * thumbH - rectH / 2

        return Rectangle()
            .stroke(Color.white, lineWidth: 1.5)
            .background(Color.white.opacity(0.15))
            .frame(width: max(rectW, 4), height: max(rectH, 4))
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
                let tapX = value.location.x
                let tapY = value.location.y
                let normX = tapX / thumbW
                let normY = tapY / thumbH
                offset = CGSize(
                    width: (0.5 - normX) * fitW * zoom,
                    height: (0.5 - normY) * fitH * zoom)
                dragStart = offset
            }
    }

    // MARK: - Gestures

    private var dividerDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Convert drag location to fraction of view width
                // We need to use the parent geometry, so we work with the
                // absolute x position from the drag
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

    // MARK: - Scroll/trackpad panning

    @State private var scrollMonitor: Any?

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Pan with scroll wheel / trackpad
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
