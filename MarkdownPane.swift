import SwiftUI
import WebKit

// MARK: - Drop overlay (sits on top of WKWebView, forwards scroll through)

private class DropOverlayView: NSView {
    var onFileDrop: ((URL) -> Void)?
    var onTargetChange: ((Bool) -> Void)?
    weak var scrollTarget: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func scrollWheel(with event: NSEvent) {
        scrollTarget?.scrollWheel(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard mdURL(from: sender) != nil else { return [] }
        onTargetChange?(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        mdURL(from: sender) != nil ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { onTargetChange?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChange?(false)
        guard let url = mdURL(from: sender) else { return false }
        onFileDrop?(url)
        return true
    }

    private func mdURL(from info: NSDraggingInfo) -> URL? {
        (info.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .first { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }
    }
}

// MARK: - Container: WKWebView for rendering + overlay for drops

private class MarkdownContainerView: NSView {
    private var webView: WKWebView!
    fileprivate var overlay: DropOverlayView!

    var onFileDrop: ((URL) -> Void)?
    var onTargetChange: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)

        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: bounds, configuration: config)
        webView.underPageBackgroundColor = NSColor.textBackgroundColor
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)

        overlay = DropOverlayView(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.scrollTarget = webView
        overlay.onFileDrop = { [weak self] url in self?.onFileDrop?(url) }
        overlay.onTargetChange = { [weak self] v in self?.onTargetChange?(v) }
        addSubview(overlay)
    }
    required init?(coder: NSCoder) { fatalError() }

    func loadHTML(_ html: String) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - NSViewRepresentable

private struct MarkdownRepresentable: NSViewRepresentable {
    let html: String?
    @Binding var isTargeted: Bool
    let onFileDrop: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MarkdownContainerView {
        let v = MarkdownContainerView()
        let coordinator = context.coordinator
        v.onFileDrop = { url in DispatchQueue.main.async { coordinator.parent.onFileDrop(url) } }
        v.onTargetChange = { val in DispatchQueue.main.async { coordinator.parent.isTargeted = val } }
        return v
    }

    func updateNSView(_ v: MarkdownContainerView, context: Context) {
        context.coordinator.parent = self
        v.onFileDrop = { url in DispatchQueue.main.async { context.coordinator.parent.onFileDrop(url) } }
        v.onTargetChange = { val in DispatchQueue.main.async { context.coordinator.parent.isTargeted = val } }
        if let html { v.loadHTML(html) } else { v.loadHTML("") }
    }

    class Coordinator: NSObject {
        var parent: MarkdownRepresentable
        init(_ p: MarkdownRepresentable) { parent = p }
    }
}

// MARK: - SwiftUI View

struct MarkdownPane: View {
    @Binding var markdownContent: String?
    @Binding var fileName: String?
    @State private var isTargeted = false

    private var html: String? {
        markdownContent.map { MarkdownConverter.toHTML($0) }
    }

    var body: some View {
        ZStack {
            MarkdownRepresentable(html: html, isTargeted: $isTargeted, onFileDrop: load)

            if markdownContent == nil {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("Drop a Markdown file")
                        .foregroundColor(.secondary)
                    Text(".md")
                        .font(.caption)
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .overlay(Rectangle().stroke(isTargeted ? Color.accentColor : .clear, lineWidth: 3))
        .overlay(alignment: .bottomTrailing) {
            if let name = fileName {
                Text(name)
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.regularMaterial).cornerRadius(4).padding(8)
            }
        }
        .contextMenu {
            if markdownContent != nil {
                Button("Clear") { markdownContent = nil; fileName = nil }
            }
        }
    }

    private func load(_ url: URL) {
        do {
            markdownContent = try String(contentsOf: url, encoding: .utf8)
            fileName = url.lastPathComponent
        } catch {
            markdownContent = "**Error:** \(error.localizedDescription)"
            fileName = url.lastPathComponent
        }
    }
}
