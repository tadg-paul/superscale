// ABOUTME: Before/after comparison: a curtain divider dragged across the image.
// ABOUTME: The original is left of the divider, the derived image right of it.

import SuperscaleUXCore
import SwiftUI

/// The comparison, which is a curtain and nothing else.
///
/// A magnifier loupe was the default until #90 removed it. The loupe hid the system cursor and
/// drew its own at the pointer, which is brittle and reads as such in use; a divider dragged
/// across the image is the instrument this comparison wants. `MagnifierView` is deleted rather
/// than left unreferenced, so a loupe returning would be a compile error rather than a review
/// question.
struct ComparisonView: View {
    let original: NSImage
    let upscaled: NSImage

    @State private var dividerPosition: CGFloat = 0.35
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var scrollMonitor: Any?
    /// Whether the pointer is within the picture's own displayed frame, which is not the same
    /// rectangle as the canvas and is not the window at all.
    @State private var pointerIsOverPicture = false

    /// The space the pointer and the picture are both measured in.
    ///
    /// Named on the container rather than left implicit, because a drag gesture reports in the
    /// space of the view it is attached to, and the divider's handle is 28 points wide.
    private static let curtainSpace = "curtain"

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                sliderContent(size: size)

                VStack {
                    HStack {
                        Spacer()
                        zoomControls
                            .padding(12)
                    }
                    Spacer()
                }
            }
            .coordinateSpace(name: Self.curtainSpace)
        }
    }

    // MARK: - The curtain

    private func sliderContent(size: CGSize) -> some View {
        // One frame for both sides. Computed from the original's aspect, so the 4x upscale is
        // presented at the same size and the divider falls on the same part of each picture.
        let imageFrame = CurtainGeometry.displayedFrame(imageSize: original.size, in: size)
        let dividerX = CurtainGeometry.dividerX(fraction: dividerPosition, in: imageFrame)

        return ZStack {
            // Upscaled image (full background)
            imageLayer(image: upscaled, size: size)

            // Original image (clipped to left of divider) — nearest-neighbour
            imageLayer(image: original, size: size, interpolation: .none)
                .clipShape(HorizontalClip(width: dividerX))

            // Divider line
            dividerOverlay(at: dividerX, height: size.height, imageFrame: imageFrame)

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
        .onContinuousHover(coordinateSpace: .named(Self.curtainSpace)) { phase in
            switch phase {
            case let .active(location):
                pointerIsOverPicture = CurtainGeometry.scrollBelongsToPicture(
                    at: location, in: imageFrame)
            case .ended:
                pointerIsOverPicture = false
            }
        }
        // The pan reaches the accessibility tree as a value. Expressed only as a rendered offset it
        // reaches nobody — not VoiceOver, and not a test asking whether the picture moved.
        .accessibilityValue("panned \(Int(offset.width)) by \(Int(offset.height))")
        // A container, not an element. Without this the identifier makes SwiftUI treat the whole
        // curtain as one element and absorb the divider, its rule and the zoom controls — the
        // defect recorded as D-2 on #79 and written into guide 3.9, reproduced here an hour after
        // that rule was written down. The suite caught it as "no curtain to drag".
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("curtainPicture")
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

    private func dividerOverlay(at x: CGFloat, height: CGFloat, imageFrame: CGRect) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: height)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .position(x: x, y: height / 2)
                .accessibilityIdentifier("curtainDividerLine")

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
                .gesture(dividerDragGesture(imageFrame: imageFrame))
                .accessibilityIdentifier("curtainDivider")
        }
    }

    // MARK: - Slider zoom controls

    private var zoomControls: some View {
        VStack(spacing: 4) {
            Button {
                zoom = min(10.0, zoom + 0.5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .accessibilityIdentifier("zoomInButton")

            Text("\(Int(zoom * 100))%")
                .font(.system(.callout, design: .monospaced).bold())
                .frame(width: 44)

            Button {
                zoom = max(1.0, zoom - 0.5)
                if zoom == 1.0 { offset = .zero; dragStart = .zero }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .accessibilityIdentifier("zoomOutButton")
        }
        .buttonStyle(.bordered)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10))
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

    /// The divider follows the pointer within the picture, not within the window.
    ///
    /// The gesture reports in `curtainSpace`, a coordinate space named on the container, so
    /// `value.location` is measured against the same rectangle `CurtainGeometry` is given. Reading
    /// the location in the handle's own space and dividing by the window's width — which is what
    /// this did — put the divider somewhere else entirely as soon as the filter panel was open.
    private func dividerDragGesture(imageFrame: CGRect) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.curtainSpace))
            .onChanged { value in
                dividerPosition = CurtainGeometry.dividerFraction(
                    pointerX: value.location.x, in: imageFrame)
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

    /// The monitor moves the picture only while the pointer is over it.
    ///
    /// It previously moved it for any scroll anywhere in the window, including over the filter
    /// category strip, which is a horizontal `ScrollView` of its own. A local `NSEvent` monitor is a
    /// global interception dressed as a view behaviour: it fires for the toolbar, the side panel,
    /// the lock chain and the status bar alike.
    ///
    /// Whether the pointer is over the picture comes from SwiftUI's own hover tracking rather than
    /// from converting the event's window coordinates. The conversion is the tempting fix and it is
    /// wrong: the curtain's space is not the window's, so any change to the toolbar's height or the
    /// panel's width would silently move the region the test is against.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard pointerIsOverPicture else { return event }

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
