import SwiftUI
import AppKit

// MARK: - Pure AppKit canvas: image rendering + gestures + drop

private class ImageCanvasView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var onFileDrop: ((URL) -> Void)?
    var onScaleUpdate: ((CGFloat) -> Void)?

    private var scale: CGFloat = 1.0
    private var rotation: CGFloat = 0.0          // radians
    private var translation: CGPoint = .zero
    private var translationAtPanStart: CGPoint = .zero
    private var isDropTarget = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        registerForDraggedTypes([.fileURL])

        let mag = NSMagnificationGestureRecognizer(target: self, action: #selector(onMag(_:)))
        addGestureRecognizer(mag)

        let rot = NSRotationGestureRecognizer(target: self, action: #selector(onRot(_:)))
        addGestureRecognizer(rot)

        let pan = NSPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        addGestureRecognizer(pan)

        let dbl = NSClickGestureRecognizer(target: self, action: #selector(onDoubleClick(_:)))
        dbl.numberOfClicksRequired = 2
        addGestureRecognizer(dbl)
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .cursorUpdate, .mouseEnteredAndExited],
            owner: self, userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    // MARK: Scroll wheel — plain scroll = pan, Cmd+scroll = zoom toward cursor

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let cursor = convert(event.locationInWindow, from: nil)
            zoomToward(cursor, factor: pow(1.02, -event.scrollingDeltaY))
        } else {
            translation.x += event.scrollingDeltaX
            translation.y += event.scrollingDeltaY
            needsDisplay = true
        }
    }

    private func zoomToward(_ point: CGPoint, factor: CGFloat) {
        let newScale = max(0.02, min(32, scale * factor))
        let ratio = newScale / scale
        // Shift translation so the point under the cursor stays fixed
        translation.x = point.x - bounds.midX - (point.x - bounds.midX - translation.x) * ratio
        translation.y = point.y - bounds.midY - (point.y - bounds.midY - translation.y) * ratio
        scale = newScale
        onScaleUpdate?(scale)
        needsDisplay = true
    }

    // MARK: Gestures

    @objc private func onMag(_ gr: NSMagnificationGestureRecognizer) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        zoomToward(center, factor: 1 + gr.magnification)
        gr.magnification = 0
    }

    @objc private func onRot(_ gr: NSRotationGestureRecognizer) {
        rotation -= gr.rotation
        gr.rotation = 0
        needsDisplay = true
    }

    @objc private func onPan(_ gr: NSPanGestureRecognizer) {
        switch gr.state {
        case .began:
            translationAtPanStart = translation
            NSCursor.closedHand.push()
        case .changed:
            let d = gr.translation(in: self)
            translation = CGPoint(x: translationAtPanStart.x + d.x, y: translationAtPanStart.y + d.y)
            needsDisplay = true
        default:
            NSCursor.pop()
        }
    }

    @objc private func onDoubleClick(_ gr: NSClickGestureRecognizer) {
        scale = 1; rotation = 0; translation = .zero
        onScaleUpdate?(1)
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        if let image {
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.saveGState()
            ctx.translateBy(x: bounds.midX + translation.x, y: bounds.midY + translation.y)
            ctx.rotate(by: rotation)
            ctx.scaleBy(x: scale, y: scale)

            let sz = image.size
            let fit = min(bounds.width / sz.width, bounds.height / sz.height) * 0.92
            let w = sz.width * fit, h = sz.height * fit
            image.draw(in: CGRect(x: -w/2, y: -h/2, width: w, height: h),
                       from: .zero, operation: .sourceOver, fraction: 1)
            ctx.restoreGState()
        } else {
            drawPlaceholder()
        }

        if isDropTarget {
            NSColor.controlAccentColor.setStroke()
            let p = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            p.lineWidth = 3; p.stroke()
        }
    }

    private func drawPlaceholder() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 44, weight: .light)
        guard let img = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return }
        let s = img.size
        img.draw(at: NSPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2),
                 from: .zero, operation: .sourceOver, fraction: 0.35)
    }

    // MARK: Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard imageURL(from: sender) != nil else { return [] }
        isDropTarget = true; needsDisplay = true
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURL(from: sender) != nil ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false; needsDisplay = true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false; needsDisplay = true
        guard let url = imageURL(from: sender) else { return false }
        scale = 1; rotation = 0; translation = .zero
        onScaleUpdate?(1)
        onFileDrop?(url)
        return true
    }

    private func imageURL(from info: NSDraggingInfo) -> URL? {
        (info.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .first { ["png","jpg","jpeg","webp","gif","tiff","heic"].contains($0.pathExtension.lowercased()) }
    }
}

// MARK: - NSViewRepresentable

private struct ImageCanvasRepresentable: NSViewRepresentable {
    @Binding var image: NSImage?
    @Binding var scale: CGFloat
    let onFileDrop: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ImageCanvasView {
        let v = ImageCanvasView()
        v.onFileDrop = { url in
            DispatchQueue.main.async { context.coordinator.parent.onFileDrop(url) }
        }
        v.onScaleUpdate = { s in
            DispatchQueue.main.async { context.coordinator.parent.scale = s }
        }
        return v
    }

    func updateNSView(_ v: ImageCanvasView, context: Context) {
        context.coordinator.parent = self
        v.image = image
        v.onFileDrop = { url in
            DispatchQueue.main.async { context.coordinator.parent.onFileDrop(url) }
        }
        v.onScaleUpdate = { s in
            DispatchQueue.main.async { context.coordinator.parent.scale = s }
        }
    }

    class Coordinator: NSObject {
        var parent: ImageCanvasRepresentable
        init(_ p: ImageCanvasRepresentable) { parent = p }
    }
}

// MARK: - SwiftUI View

struct ImagePane: View {
    @State private var image: NSImage? = nil
    @State private var fileName: String? = nil
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ImageCanvasRepresentable(image: $image, scale: $scale) { url in
                if let img = NSImage(contentsOf: url) {
                    image = img
                    fileName = url.lastPathComponent
                    scale = 1
                }
            }

            if image == nil {
                VStack(spacing: 10) {
                    Text("Drop an image")
                        .foregroundColor(.secondary)
                    Text(".png  ·  .jpg  ·  .webp")
                        .font(.caption)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .padding(.top, 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
            }

            if image != nil {
                VStack(alignment: .trailing, spacing: 3) {
                    if let name = fileName { Text(name).font(.caption2).foregroundColor(.secondary) }
                    Text(String(format: "%.0f%%", scale * 100))
                        .font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(.regularMaterial).cornerRadius(4).padding(8)
                .allowsHitTesting(false)
            }
        }
        .contextMenu {
            if image != nil {
                Button("Clear") { image = nil; fileName = nil; scale = 1 }
            }
        }
    }
}
