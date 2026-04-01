// ABOUTME: Before/after comparison view with draggable vertical divider.
// ABOUTME: Overlays original and upscaled images with synchronised zoom and pan.

import SwiftUI

struct ComparisonView: View {
    let original: NSImage
    let upscaled: NSImage

    @State private var dividerPosition: CGFloat = 0.5
    @State private var zoom: CGFloat = 1.0
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
        HStack(spacing: 4) {
            Button {
                zoom = max(1.0, zoom - 0.5)
                if zoom == 1.0 { offset = .zero; dragStart = .zero }
            } label: {
                Text("−")
            }

            Text("\(Int(zoom * 100))%")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 44)

            Button {
                zoom = min(10.0, zoom + 0.5)
            } label: {
                Text("+")
            }
        }
        .buttonStyle(.bordered)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
