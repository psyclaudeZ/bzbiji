import SwiftUI
import AppKit
import WebKit

// MARK: - DropSide

enum DropSide { case left, center, right }

// MARK: - Image drawing layer (pure rendering, no event handling)

private class ImageLayerView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var xScale: CGFloat = 1
    var xRotation: CGFloat = 0
    var xTranslation: CGPoint = .zero

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        guard let image else { return }
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.clip(to: bounds)  // prevent image bleeding into adjacent panes
        ctx.translateBy(x: bounds.midX + xTranslation.x, y: bounds.midY + xTranslation.y)
        ctx.rotate(by: xRotation)
        ctx.scaleBy(x: xScale, y: xScale)
        let sz = image.size
        let fit = min(bounds.width / sz.width, bounds.height / sz.height) * 0.92
        let w = sz.width * fit, h = sz.height * fit
        image.draw(in: CGRect(x: -w/2, y: -h/2, width: w, height: h),
                   from: .zero, operation: .sourceOver, fraction: 1)
        ctx.restoreGState()
    }
}

// MARK: - Interaction overlay (sits on top: handles drag, gestures, draw indicator)

private class PaneOverlay: NSView {
    enum ContentKind { case empty, markdown, image }
    var contentKind: ContentKind = .empty
    var isSplit: Bool = false

    // Refs to content views below (set by UnifiedPaneNSView)
    weak var imageLayer: ImageLayerView?
    weak var webView: WKWebView?

    // Image transform
    private var imgScale: CGFloat = 1
    private var imgRotation: CGFloat = 0
    private var imgTranslation: CGPoint = .zero
    private var imgTranslationAtStart: CGPoint = .zero

    // Drag state
    private var isDragTarget = false
    private var dragSide: DropSide? = nil

    // Callbacks
    var onDrop: ((URL, DropSide) -> Void)?
    var onScaleChange: ((CGFloat) -> Void)?

    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])

        let mag = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMag(_:)))
        addGestureRecognizer(mag)
        let rot = NSRotationGestureRecognizer(target: self, action: #selector(handleRot(_:)))
        addGestureRecognizer(rot)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        let dbl = NSClickGestureRecognizer(target: self, action: #selector(handleDouble(_:)))
        dbl.numberOfClicksRequired = 2
        addGestureRecognizer(dbl)

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .cursorUpdate, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Transform

    func resetImageTransform() {
        imgScale = 1; imgRotation = 0; imgTranslation = .zero
        pushImageTransform()
    }

    private func pushImageTransform() {
        guard let layer = imageLayer else { return }
        layer.xScale = imgScale
        layer.xRotation = imgRotation
        layer.xTranslation = imgTranslation
        layer.needsDisplay = true
        onScaleChange?(imgScale)
    }

    // MARK: Cursor

    override func cursorUpdate(with event: NSEvent) {
        if contentKind == .image { NSCursor.openHand.set() }
    }

    // MARK: Scroll

    override func scrollWheel(with event: NSEvent) {
        switch contentKind {
        case .image:
            if event.modifierFlags.contains(.command) {
                zoomToward(convert(event.locationInWindow, from: nil),
                           factor: pow(1.02, -event.scrollingDeltaY))
            } else {
                imgTranslation.x += event.scrollingDeltaX
                imgTranslation.y += event.scrollingDeltaY
                pushImageTransform()
            }
        case .markdown:
            webView?.scrollWheel(with: event)
        case .empty:
            super.scrollWheel(with: event)
        }
    }

    private func zoomToward(_ pt: CGPoint, factor: CGFloat) {
        let newScale = max(0.02, min(32, imgScale * factor))
        let ratio = newScale / imgScale
        imgTranslation.x = pt.x - bounds.midX - (pt.x - bounds.midX - imgTranslation.x) * ratio
        imgTranslation.y = pt.y - bounds.midY - (pt.y - bounds.midY - imgTranslation.y) * ratio
        imgScale = newScale
        pushImageTransform()
    }

    // MARK: Gestures

    @objc private func handleMag(_ gr: NSMagnificationGestureRecognizer) {
        guard contentKind == .image else { return }
        zoomToward(CGPoint(x: bounds.midX, y: bounds.midY), factor: 1 + gr.magnification)
        gr.magnification = 0
    }

    @objc private func handleRot(_ gr: NSRotationGestureRecognizer) {
        guard contentKind == .image else { return }
        imgRotation -= gr.rotation; gr.rotation = 0
        pushImageTransform()
    }

    @objc private func handlePan(_ gr: NSPanGestureRecognizer) {
        guard contentKind == .image else { return }
        switch gr.state {
        case .began:
            imgTranslationAtStart = imgTranslation
            NSCursor.closedHand.push()
        case .changed:
            let d = gr.translation(in: self)
            imgTranslation = CGPoint(x: imgTranslationAtStart.x + d.x, y: imgTranslationAtStart.y + d.y)
            pushImageTransform()
        default:
            NSCursor.pop()
        }
    }

    @objc private func handleDouble(_ gr: NSClickGestureRecognizer) {
        guard contentKind == .image else { return }
        imgScale = 1; imgRotation = 0; imgTranslation = .zero
        pushImageTransform()
    }

    // MARK: Drag & Drop

    private func computeSide(at location: NSPoint) -> DropSide {
        if isSplit { return .center }
        if location.x < bounds.width / 3 { return .left }
        if location.x > bounds.width * 2 / 3 { return .right }
        return .center
    }

    private func acceptURL(from info: NSDraggingInfo) -> URL? {
        (info.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .first { PaneContent(url: $0) != nil }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptURL(from: sender) != nil else { return [] }
        isDragTarget = true
        let loc = convert(sender.draggingLocation, from: nil)
        dragSide = contentKind != .empty ? computeSide(at: loc) : nil
        needsDisplay = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptURL(from: sender) != nil else { return [] }
        let loc = convert(sender.draggingLocation, from: nil)
        dragSide = contentKind != .empty ? computeSide(at: loc) : nil
        needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragTarget = false; dragSide = nil; needsDisplay = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let side = dragSide ?? .center
        isDragTarget = false; dragSide = nil; needsDisplay = true
        guard let url = acceptURL(from: sender) else { return false }
        onDrop?(url, side)
        return true
    }

    // MARK: Drawing (indicator only; transparent otherwise)

    override func draw(_ dirtyRect: NSRect) {
        guard isDragTarget else { return }

        let half = bounds.width / 2

        if let side = dragSide {
            let highlight: NSRect
            switch side {
            case .left:   highlight = NSRect(x: 0,    y: 0, width: half, height: bounds.height)
            case .right:  highlight = NSRect(x: half, y: 0, width: half, height: bounds.height)
            case .center: highlight = bounds
            }
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            highlight.fill()

            if side != .center {
                NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke()
                let divider = NSBezierPath()
                divider.move(to: NSPoint(x: half, y: 0))
                divider.line(to: NSPoint(x: half, y: bounds.height))
                divider.lineWidth = 2
                divider.stroke()
            }
        } else {
            // Empty pane: full highlight
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }

        // Outer border
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        border.lineWidth = 3
        border.stroke()
    }
}

// MARK: - Unified NSView container

class UnifiedPaneNSView: NSView {
    private var webView: WKWebView?
    private let imageLayer: ImageLayerView
    fileprivate let overlay: PaneOverlay

    private(set) var currentContent: PaneContent = .empty

    override init(frame: NSRect) {
        imageLayer = ImageLayerView(frame: .zero)
        overlay = PaneOverlay(frame: .zero)
        super.init(frame: frame)

        for v in [imageLayer, overlay] as [NSView] {
            v.autoresizingMask = [.width, .height]
            v.frame = bounds
        }
        imageLayer.isHidden = true

        addSubview(imageLayer)
        addSubview(overlay)

        overlay.imageLayer = imageLayer
    }

    private func ensureWebView() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: bounds, configuration: config)
        wv.underPageBackgroundColor = NSColor.textBackgroundColor
        wv.appearance = NSApp.effectiveAppearance  // match system appearance explicitly
        wv.autoresizingMask = [.width, .height]
        wv.isHidden = true
        webView = wv
        addSubview(wv, positioned: .below, relativeTo: imageLayer)
        overlay.webView = wv
    }
    required init?(coder: NSCoder) { fatalError() }

    func setContent(_ content: PaneContent) {
        currentContent = content
        switch content {
        case .empty:
            webView?.isHidden = true
            imageLayer.isHidden = true
            imageLayer.image = nil
            overlay.contentKind = .empty
        case .markdown(let text, _):
            ensureWebView()
            webView?.isHidden = false
            imageLayer.isHidden = true
            imageLayer.image = nil
            overlay.contentKind = .markdown
            webView?.loadHTMLString(MarkdownConverter.toHTML(text), baseURL: nil)
        case .image(let img, _):
            webView?.isHidden = true
            imageLayer.isHidden = false
            overlay.contentKind = .image
            let changed = imageLayer.image !== img
            imageLayer.image = img
            if changed { overlay.resetImageTransform() }
        }
    }
}

// MARK: - NSViewRepresentable

struct UnifiedPaneRepresentable: NSViewRepresentable {
    @Binding var content: PaneContent
    var isSplit: Bool
    var onDrop: (URL, DropSide) -> Void
    var onScaleChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: UnifiedPaneRepresentable
        init(_ p: UnifiedPaneRepresentable) { parent = p }
    }

    func makeNSView(context: Context) -> UnifiedPaneNSView {
        let v = UnifiedPaneNSView()
        attach(v, to: context.coordinator)
        return v
    }

    func updateNSView(_ v: UnifiedPaneNSView, context: Context) {
        context.coordinator.parent = self
        attach(v, to: context.coordinator)
        v.overlay.isSplit = isSplit
        if v.currentContent != content { v.setContent(content) }
    }

    private func attach(_ v: UnifiedPaneNSView, to coordinator: Coordinator) {
        v.overlay.onDrop = { url, side in
            DispatchQueue.main.async { coordinator.parent.onDrop(url, side) }
        }
        v.overlay.onScaleChange = { s in
            DispatchQueue.main.async { coordinator.parent.onScaleChange(s) }
        }
    }
}

// MARK: - UnifiedPane (SwiftUI)

struct UnifiedPane: View {
    @Binding var content: PaneContent
    var isSplit: Bool
    var onDrop: (URL, DropSide) -> Void
    var onClose: (() -> Void)?

    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(NSColor.textBackgroundColor)  // base background (NSView has no draw override)

            UnifiedPaneRepresentable(
                content: $content,
                isSplit: isSplit,
                onDrop: onDrop,
                onScaleChange: { scale = $0 }
            )

            if case .empty = content { placeholder }

            badge
        }
        .contextMenu {
            if case .empty = content {} else {
                Button("Clear") { content = .empty }
            }
            if let onClose {
                if case .empty = content {} else { Divider() }
                Button("Close Pane") { onClose() }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Drop a file")
                .foregroundColor(.secondary)
            Text(".md  ·  .png  ·  .jpg  ·  .webp")
                .font(.caption)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var badge: some View {
        switch content {
        case .empty:
            EmptyView()
        case .markdown(_, let name):
            Text(name)
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(.regularMaterial).cornerRadius(4).padding(8)
                .allowsHitTesting(false)
        case .image(_, let name):
            VStack(alignment: .trailing, spacing: 3) {
                Text(name).font(.caption2).foregroundColor(.secondary)
                Text(String(format: "%.0f%%", scale * 100))
                    .font(.caption2.monospacedDigit()).foregroundColor(.secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.regularMaterial).cornerRadius(4).padding(8)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - TabPaneContainer (SwiftUI)

struct TabPaneContainer: View {
    @Binding var tab: TabContent

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tab.panes.indices, id: \.self) { i in
                UnifiedPane(
                    content: $tab.panes[i],
                    isSplit: tab.isSplit,
                    onDrop: { url, side in handleDrop(url: url, paneIndex: i, side: side) },
                    onClose: tab.isSplit ? { closePane(at: i) } : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if i < tab.panes.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDrop(url: URL, paneIndex: Int, side: DropSide) {
        guard let newContent = PaneContent(url: url) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            switch side {
            case .center:
                tab.panes[paneIndex] = newContent
            case .left:
                tab.panes.insert(newContent, at: paneIndex)
            case .right:
                tab.panes.insert(newContent, at: paneIndex + 1)
            }
        }
    }

    private func closePane(at index: Int) {
        guard tab.panes.count > 1 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            _ = tab.panes.remove(at: index)
        }
    }
}
