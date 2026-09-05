import SwiftUI
import AppKit
import WebKit

// MARK: - Pane palette

enum AppPalette {
    // Warm content surfaces. Keeping these centralized ensures the SwiftUI
    // canvas, AppKit image canvas, and WebKit scrollbar gutter match.
    private static let lightContent = NSColor(
        srgbRed: 245.0 / 255.0,
        green: 242.0 / 255.0,
        blue: 234.0 / 255.0,
        alpha: 1
    )
    private static let darkContent = NSColor(
        srgbRed: 38.0 / 255.0,
        green: 37.0 / 255.0,
        blue: 34.0 / 255.0,
        alpha: 1
    )
    private static let lightChrome = NSColor(
        srgbRed: 236.0 / 255.0,
        green: 232.0 / 255.0,
        blue: 223.0 / 255.0,
        alpha: 1
    )
    private static let darkChrome = NSColor(
        srgbRed: 31.0 / 255.0,
        green: 30.0 / 255.0,
        blue: 28.0 / 255.0,
        alpha: 1
    )

    static func background(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? darkContent : lightContent
    }

    static let background = NSColor(name: nil) { appearance in
        background(for: appearance)
    }

    static let tabBarBackground = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? darkChrome : lightChrome
    }
}

// MARK: - DropSide

enum DropSide { case left, center, right }

// MARK: - Persistent markdown zoom (shared across all panes and launches)

private extension Notification.Name {
    static let bzbijiMdZoomChanged = Notification.Name("bzbiji.mdZoomChanged")
}

private enum MdZoomStore {
    static let key = "bzbiji.mdZoom"
    static let min: CGFloat = 0.25
    static let max: CGFloat = 4.0

    static func load() -> CGFloat {
        let v = UserDefaults.standard.double(forKey: key)
        return (v >= Double(min) && v <= Double(max)) ? CGFloat(v) : 1.0
    }

    static func save(_ v: CGFloat) {
        UserDefaults.standard.set(Double(v), forKey: key)
        NotificationCenter.default.post(name: .bzbijiMdZoomChanged, object: v)
    }
}

// MARK: - Image drawing layer (pure rendering, no event handling)

private class ImageLayerView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var xScale: CGFloat = 1
    var xRotation: CGFloat = 0
    var xTranslation: CGPoint = .zero

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        AppPalette.background(for: effectiveAppearance).setFill()
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

// MARK: - Search bar

private class SearchField: NSTextField {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private class SearchBarView: NSView, NSTextFieldDelegate {
    private let field = SearchField()
    private let countLabel = NSTextField(labelWithString: "")
    var onQueryChange: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrev: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        field.placeholderString = "Search…"
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.delegate = self
        field.onEscape = { [weak self] in self?.onClose?() }
        field.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let prevBtn = makeArrowButton(systemName: "chevron.up", action: #selector(didPrev))
        let nextBtn = makeArrowButton(systemName: "chevron.down", action: #selector(didNext))
        let closeBtn = makeArrowButton(systemName: "xmark", action: #selector(didClose))

        let stack = NSStackView(views: [field, countLabel, prevBtn, nextBtn, closeBtn])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeArrowButton(systemName: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.target = self
        btn.action = action
        btn.contentTintColor = .secondaryLabelColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 22),
            btn.heightAnchor.constraint(equalToConstant: 22),
        ])
        return btn
    }

    func focusField() { window?.makeFirstResponder(field) }

    func updateCount(found: Bool, query: String) {
        countLabel.stringValue = query.isEmpty ? "" : (found ? "" : "No results")
    }

    // NSTextFieldDelegate
    func controlTextDidChange(_ obj: Notification) {
        onQueryChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let modifiers = NSApp.currentEvent?.modifierFlags
                .intersection(.deviceIndependentFlagsMask) ?? []
            if modifiers.contains(.shift) { onPrev?() }
            else                           { onNext?() }
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:))  { onClose?(); return true }
        if selector == #selector(NSResponder.moveUp(_:))           { onPrev?();  return true }
        if selector == #selector(NSResponder.moveDown(_:))         { onNext?();  return true }
        return false
    }

    @objc private func didPrev()  { onPrev?() }
    @objc private func didNext()  { onNext?() }
    @objc private func didClose() { onClose?() }

    override func cancelOperation(_ sender: Any?) { onClose?() }
}

// MARK: - Interaction overlay (sits on top: handles drag, gestures, draw indicator)

private class PaneOverlay: NSView {
    enum ContentKind { case empty, markdown, image }
    var contentKind: ContentKind = .empty
    var isSplit: Bool = false

    // Which edges face a sibling pane; the focus border only marks those.
    var hasLeftNeighbor = false
    var hasRightNeighbor = false

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

    // Global focus tracking — bypasses SwiftUI for instant visual update
    private static weak var activeFocusOverlay: PaneOverlay?

    // Callbacks
    var onDrop: ((URL, DropSide) -> Void)?
    var onScaleChange: ((CGFloat) -> Void)?
    var onFocus: (() -> Void)?

    var isFocused: Bool = false {
        didSet {
            guard oldValue != isFocused else { return }
            needsDisplay = true
            if isFocused { registerKeyMonitor() } else { unregisterKeyMonitor() }
        }
    }

    private var keyMonitor: Any?
    private var lastKey: String = ""

    private func registerKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isFocused else { return event }
            let key = event.charactersIgnoringModifiers ?? ""
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Escape closes the search bar if open (handled before NSTextView guard
            // because WKWebView's internal responder IS an NSTextView subclass).
            if event.keyCode == 53, self.searchBar != nil {
                self.hideSearch()
                return nil
            }
            // ⌘+/⌘-/⌘0 zoom — handled before NSTextView guard so WKWebView's internal
            // text responder doesn't swallow these events.
            if mods.contains(.command) {
                let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
                switch self.contentKind {
                case .image:
                    switch key {
                    case "=", "+": self.zoomToward(center, factor: 1.25); return nil
                    case "-":      self.zoomToward(center, factor: 0.8);  return nil
                    case "0":      self.resetImageTransform();             return nil
                    default: break
                    }
                case .markdown:
                    switch key {
                    case "=", "+": self.mdZoomBy(1.25); return nil
                    case "-":      self.mdZoomBy(0.8);  return nil
                    case "0":      self.mdZoomReset();  return nil
                    case "f":      self.showSearch();   return nil
                    default: break
                    }
                case .empty: break
                }
            }
            // Vim motions: bail if an actual text-editing field (e.g. tab rename) is active.
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            let line: CGFloat = 60
            switch key {
            case "j": self.vimScroll(dx: 0,    dy:  line); self.lastKey = key; return nil
            case "k": self.vimScroll(dx: 0,    dy: -line); self.lastKey = key; return nil
            case "h": self.vimScroll(dx: -line, dy: 0);    self.lastKey = key; return nil
            case "l": self.vimScroll(dx:  line, dy: 0);    self.lastKey = key; return nil
            case "d": self.vimScrollHalfPage(down: true);  self.lastKey = key; return nil
            case "u": self.vimScrollHalfPage(down: false); self.lastKey = key; return nil
            case "G": self.vimScrollEdge(bottom: true);    self.lastKey = key; return nil
            case "g":
                if self.lastKey == "g" { self.vimScrollEdge(bottom: false); self.lastKey = "" }
                else                   { self.lastKey = key }
                return nil
            default:  self.lastKey = key; return event
            }
        }
    }

    private func unregisterKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    deinit { unregisterKeyMonitor() }

    private func vimScrollHalfPage(down: Bool) {
        switch contentKind {
        case .markdown:
            let dir = down ? "" : "-"
            webView?.evaluateJavaScript("window.scrollBy(0, \(dir)window.innerHeight / 2)", completionHandler: nil)
        case .image:
            let dy = (down ? -1 : 1) * bounds.height / 2
            imgTranslation.y += dy
            pushImageTransform()
        case .empty: break
        }
    }

    private func vimScrollEdge(bottom: Bool) {
        switch contentKind {
        case .markdown:
            let js = bottom ? "window.scrollTo(0, document.body.scrollHeight)"
                            : "window.scrollTo(0, 0)"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        case .image:
            imgTranslation.y = bottom ? -(bounds.height / 2) : (bounds.height / 2)
            pushImageTransform()
        case .empty: break
        }
    }

    private func vimScroll(dx: CGFloat, dy: CGFloat) {
        switch contentKind {
        case .markdown:
            webView?.evaluateJavaScript("window.scrollBy(\(dx), \(dy))", completionHandler: nil)
        case .image:
            imgTranslation.x -= dx
            imgTranslation.y += dy
            pushImageTransform()
        case .empty:
            break
        }
    }

    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)

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

        NotificationCenter.default.addObserver(
            forName: .bzbijiMdZoomChanged, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let v = note.object as? CGFloat, v != self.mdZoom else { return }
            self.mdZoom = v
            self.webView?.pageZoom = v
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Focus

    override func mouseDown(with event: NSEvent) {
        // FIXME: focus border on click is visually sluggish (~100ms+).
        // Direct display() calls and deferred SwiftUI sync don't help.
        // Suspected cause: something upstream (gesture recognizers? AppKit event dispatch?
        // compositor scheduling?) is delaying the repaint despite display() being called.
        // Arrow key focus (pure SwiftUI path) is fast — investigate why mouse is different.
        handleClickFocus()
        super.mouseDown(with: event)
    }

    // Called from FocusableWebView too — markdown clicks bypass overlay's mouseDown
    // because hitTest passes them through to the webView for text selection.
    func handleClickFocus() {
        if PaneOverlay.activeFocusOverlay !== self {
            PaneOverlay.activeFocusOverlay?.isFocused = false
            PaneOverlay.activeFocusOverlay?.display()
            PaneOverlay.activeFocusOverlay = self
            isFocused = true
            display()
        }
        DispatchQueue.main.async { self.onFocus?() }
    }

    // For markdown panes, let clicks fall through to the WKWebView so text
    // selection works. Search bar and image panes still hit-test normally.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === self, contentKind == .markdown { return webView }
        return hit
    }

    // MARK: Search

    private var searchBar: SearchBarView?
    private var lastSearchQuery = ""

    func showSearch() {
        guard contentKind == .markdown else { return }
        if searchBar == nil {
            let bar = SearchBarView(frame: .zero)
            bar.onQueryChange = { [weak self] q in self?.performSearch(q, backwards: false) }
            bar.onNext  = { [weak self] in self?.performSearch(self?.lastSearchQuery ?? "", backwards: false) }
            bar.onPrev  = { [weak self] in self?.performSearch(self?.lastSearchQuery ?? "", backwards: true) }
            bar.onClose = { [weak self] in self?.hideSearch() }
            addSubview(bar)
            searchBar = bar
        }
        layoutSearchBar()
        // Defer focus so cmd+f keyUp events don't leak an "f" into the field.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.searchBar?.focusField()
        }
    }

    func hideSearch() {
        window?.makeFirstResponder(self)
        searchBar?.removeFromSuperview()
        searchBar = nil
        lastSearchQuery = ""
        webView?.evaluateJavaScript("window.__bzbijiClearHits && window.__bzbijiClearHits()",
                                    completionHandler: nil)
    }

    private func layoutSearchBar() {
        guard let bar = searchBar else { return }
        let w: CGFloat = 340, h: CGFloat = 42
        bar.frame = CGRect(x: bounds.width - w - 16, y: bounds.height - h - 12, width: w, height: h)
    }

    override func layout() {
        super.layout()
        layoutSearchBar()
    }

    private func performSearch(_ query: String, backwards: Bool) {
        lastSearchQuery = query
        guard let wv = webView else { return }
        if query.isEmpty {
            wv.evaluateJavaScript("window.__bzbijiClearHits && window.__bzbijiClearHits()",
                                  completionHandler: nil)
            searchBar?.updateCount(found: true, query: "")
            return
        }
        let queryJSON = (try? JSONEncoder().encode(query))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let dir = backwards ? -1 : 1
        let js = "window.__bzbijiSearch ? window.__bzbijiSearch(\(queryJSON), \(dir)) : 0"
        wv.evaluateJavaScript(js) { [weak self] result, _ in
            let count = (result as? Int) ?? 0
            self?.searchBar?.updateCount(found: count > 0, query: query)
        }
    }

    // MARK: Transform

    private var mdZoom: CGFloat = MdZoomStore.load()

    private func mdZoomBy(_ factor: CGFloat) {
        mdZoom = Swift.max(MdZoomStore.min, Swift.min(MdZoomStore.max, mdZoom * factor))
        webView?.pageZoom = mdZoom
        MdZoomStore.save(mdZoom)
    }

    func mdZoomReset() {
        mdZoom = 1.0
        webView?.pageZoom = 1.0
        MdZoomStore.save(1.0)
    }

    func applyMdZoom() { webView?.pageZoom = mdZoom }

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
        if isDragTarget {
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

            // Outer drag border
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
            border.lineWidth = 3
            border.stroke()
        } else if isFocused && isSplit {
            // Focus border, tmux-style: only dividers shared with a sibling are
            // marked, never the window edges, and each divider is split between
            // its two neighbours — the pane on its left claims the top half, the
            // pane on its right claims the bottom half. So a focused pane shows
            // a half-height segment per divider it touches.
            NSColor.controlAccentColor.withAlphaComponent(0.8).setFill()
            let w: CGFloat = 2
            let half = bounds.height / 2
            if hasRightNeighbor {
                NSRect(x: bounds.width - w, y: half, width: w, height: half).fill()
            }
            if hasLeftNeighbor {
                NSRect(x: 0, y: 0, width: w, height: half).fill()
            }
        }
    }
}

// MARK: - WKWebView subclass for focus tracking

private class FocusableWebView: WKWebView {
    var onMouseDown: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

private final class ScrollMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: UnifiedPaneNSView?

    init(owner: UnifiedPaneNSView) {
        self.owner = owner
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        owner?.receiveScrollMessage(message)
    }
}

// MARK: - Unified NSView container

class UnifiedPaneNSView: NSView, WKNavigationDelegate {
    private static let scrollMessageName = "bzbijiScroll"

    private var webView: FocusableWebView?
    private let imageLayer: ImageLayerView
    fileprivate let overlay: PaneOverlay
    private lazy var scrollMessageProxy = ScrollMessageProxy(owner: self)
    private var scrollPositionToRestore: PaneScrollPosition = .zero
    private var isRestoringScrollPosition = false

    private(set) var currentContent: PaneContent = .empty

    // File watching (markdown only)
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedURL: URL?
    private var pollTimer: Timer?
    var onContentReload: ((PaneContent) -> Void)?
    var onScrollPositionChange: ((PaneScrollPosition) -> Void)?

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

        // Drag-drop registered here (not on overlay) because overlay's hitTest
        // passes markdown clicks through to webView, removing overlay from the
        // drag responder chain.
        registerForDraggedTypes([.fileURL])

    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Wait until AppKit has fully propagated the new appearance through the
        // window, then re-resolve colors in that appearance's drawing context.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyWebAppearance(self.effectiveAppearance)
        }
    }

    // Drag-drop forwarders to overlay (which owns indicator drawing & drop logic).
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        overlay.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        overlay.draggingUpdated(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        overlay.draggingExited(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        overlay.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        overlay.performDragOperation(sender)
    }

    deinit {
        stopWatching()
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.scrollMessageName
        )
    }

    private func applyWebAppearance(_ appearance: NSAppearance) {
        guard let webView else { return }
        webView.appearance = appearance

        appearance.performAsCurrentDrawingAppearance {
            // WKWebView copies this value, so assign it again to avoid retaining
            // the concrete color resolved under the previous system theme.
            webView.underPageBackgroundColor = AppPalette.background(for: appearance)
        }

        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colorScheme = isDark ? "dark" : "light"
        webView.evaluateJavaScript(
            "document.documentElement.style.colorScheme = '\(colorScheme)'",
            completionHandler: nil
        )
        webView.needsDisplay = true
    }

    private func ensureWebView() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        let scrollScript = WKUserScript(
            source: """
            (function() {
              var timer = null;
              function reportScroll() {
                timer = null;
                window.webkit.messageHandlers.bzbijiScroll.postMessage({
                  x: window.scrollX,
                  y: window.scrollY
                });
              }
              window.addEventListener('scroll', function() {
                if (timer !== null) clearTimeout(timer);
                timer = setTimeout(reportScroll, 100);
              }, { passive: true });
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(scrollScript)
        config.userContentController.add(scrollMessageProxy, name: Self.scrollMessageName)
        let wv = FocusableWebView(frame: bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.isHidden = true
        // Stop WKWebView from intercepting file drops (so they bubble to parent).
        wv.unregisterDraggedTypes()
        wv.onMouseDown = { [weak self] in self?.overlay.handleClickFocus() }
        wv.navigationDelegate = self
        webView = wv
        addSubview(wv, positioned: .below, relativeTo: imageLayer)
        overlay.webView = wv
        applyWebAppearance(effectiveAppearance)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setContent(_ content: PaneContent,
                    restoring scrollPosition: PaneScrollPosition = .zero) {
        currentContent = content
        switch content {
        case .empty:
            stopWatching()
            webView?.isHidden = true
            imageLayer.isHidden = true
            imageLayer.image = nil
            overlay.contentKind = .empty
        case .markdown(let text, _, let url):
            ensureWebView()
            scrollPositionToRestore = scrollPosition.sanitized
            isRestoringScrollPosition = true
            webView?.isHidden = false
            imageLayer.isHidden = true
            imageLayer.image = nil
            overlay.contentKind = .markdown
            overlay.applyMdZoom()
            webView?.loadHTMLString(MarkdownConverter.toHTML(text), baseURL: nil)
            startWatching(url)
        case .image(let img, _, _):
            stopWatching()
            webView?.isHidden = true
            imageLayer.isHidden = false
            overlay.contentKind = .image
            let changed = imageLayer.image !== img
            imageLayer.image = img
            if changed { overlay.resetImageTransform() }
        }
    }

    fileprivate func receiveScrollMessage(_ message: WKScriptMessage) {
        guard !isRestoringScrollPosition,
              message.frameInfo.isMainFrame,
              case .markdown = currentContent,
              let body = message.body as? [String: Any],
              let x = body["x"] as? NSNumber,
              let y = body["y"] as? NSNumber else { return }
        let position = PaneScrollPosition(
            x: x.doubleValue,
            y: y.doubleValue
        ).sanitized
        scrollPositionToRestore = position
        onScrollPositionChange?(position)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard case .markdown = currentContent else { return }
        // A new document replaces the inline color-scheme override.
        applyWebAppearance(effectiveAppearance)
        let position = scrollPositionToRestore.sanitized
        let js = """
        (function() {
          var oldBehavior = document.documentElement.style.scrollBehavior;
          document.documentElement.style.scrollBehavior = 'auto';
          window.scrollTo(\(position.x), \(position.y));
          document.documentElement.style.scrollBehavior = oldBehavior;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            // Let the scroll event generated by restoration drain before live
            // scroll messages are accepted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.isRestoringScrollPosition = false
            }
        }
    }

    // MARK: - File watching (live reload for markdown)

    private func stopWatching() {
        fileSource?.cancel()
        fileSource = nil
        pollTimer?.invalidate()
        pollTimer = nil
        watchedURL = nil
    }

    private func startWatching(_ url: URL) {
        if watchedURL == url, fileSource != nil { return }
        stopWatching()
        watchedURL = url
        attachWatcher(to: url)
        // Polling backstop: dispatch sources can miss events when the editor uses
        // atomic-rename + creates a *new* file each save (the path's underlying
        // inode keeps changing). 1s mtime check is essentially free.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reloadFromDisk(url)
        }
    }

    private func attachWatcher(to url: URL, retries: Int = 5) {
        guard watchedURL == url else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File may be momentarily missing during atomic save (vim's write-temp+rename)
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.attachWatcher(to: url, retries: retries - 1)
                }
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let mask = src.data
            self.reloadFromDisk(url)
            // vim/nvim writes a new file then renames over the old — the original inode is
            // gone, so we must re-open and re-watch the path.
            if mask.contains(.delete) || mask.contains(.rename) {
                self.fileSource?.cancel()
                self.fileSource = nil
                self.attachWatcher(to: url)
            }
        }
        src.setCancelHandler { close(fd) }
        fileSource = src
        src.resume()
    }

    private func reloadFromDisk(_ url: URL) {
        guard case .markdown(let oldText, let name, let curURL) = currentContent,
              curURL == url else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              text != oldText else { return }
        let new = PaneContent.markdown(content: text, fileName: name, url: url)
        currentContent = new
        onContentReload?(new)

        let body = MarkdownConverter.toBodyHTML(text)
        guard let bodyData = try? JSONEncoder().encode(body),
              let bodyJSON = String(data: bodyData, encoding: .utf8) else { return }
        // In-place swap preserves scroll position; window.* search functions survive
        // because innerHTML replacement only touches the content div, not the script tag.
        let js = """
        (function() {
          var y = window.scrollY;
          if (window.__bzbijiClearHits) window.__bzbijiClearHits();
          var el = document.getElementById('bzbiji-content');
          if (el) { el.innerHTML = \(bodyJSON); window.scrollTo(0, y); }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

// MARK: - NSViewRepresentable

struct UnifiedPaneRepresentable: NSViewRepresentable {
    @Binding var content: PaneContent
    @Binding var scrollPosition: PaneScrollPosition
    var isActive: Bool
    var isSplit: Bool
    var isFocused: Bool
    var hasLeftNeighbor: Bool
    var hasRightNeighbor: Bool
    var onDrop: (URL, DropSide) -> Void
    var onScaleChange: (CGFloat) -> Void
    var onFocus: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: UnifiedPaneRepresentable
        init(_ p: UnifiedPaneRepresentable) { parent = p }
    }

    func makeNSView(context: Context) -> UnifiedPaneNSView {
        let v = UnifiedPaneNSView()
        v.isHidden = !isActive
        attach(v, to: context.coordinator)
        return v
    }

    func updateNSView(_ v: UnifiedPaneNSView, context: Context) {
        context.coordinator.parent = self
        attach(v, to: context.coordinator)
        // SwiftUI opacity does not reliably hide WKWebView's out-of-process
        // scrollbar. AppKit visibility does, while retaining the native view
        // and its scroll position for the next tab switch.
        v.isHidden = !isActive
        v.overlay.isSplit = isSplit
        v.overlay.isFocused = isFocused
        v.overlay.hasLeftNeighbor = hasLeftNeighbor
        v.overlay.hasRightNeighbor = hasRightNeighbor
        v.overlay.needsDisplay = true
        if v.currentContent != content {
            v.setContent(content, restoring: scrollPosition)
        }
    }

    private func attach(_ v: UnifiedPaneNSView, to coordinator: Coordinator) {
        v.overlay.onDrop = { url, side in
            DispatchQueue.main.async { coordinator.parent.onDrop(url, side) }
        }
        v.overlay.onScaleChange = { s in
            DispatchQueue.main.async { coordinator.parent.onScaleChange(s) }
        }
        v.overlay.onFocus = { coordinator.parent.onFocus() }
        v.onContentReload = { new in
            DispatchQueue.main.async { coordinator.parent.content = new }
        }
        v.onScrollPositionChange = { position in
            DispatchQueue.main.async { coordinator.parent.scrollPosition = position }
        }
    }
}

// MARK: - UnifiedPane (SwiftUI)

struct UnifiedPane: View {
    @Binding var content: PaneContent
    @Binding var scrollPosition: PaneScrollPosition
    var isActive: Bool = true
    var isSplit: Bool
    var isFocused: Bool
    var hasLeftNeighbor: Bool = false
    var hasRightNeighbor: Bool = false
    var onDrop: (URL, DropSide) -> Void
    var onFocus: () -> Void
    var onClose: (() -> Void)?

    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(AppPalette.background)  // base background (NSView has no draw override)

            UnifiedPaneRepresentable(
                content: $content,
                scrollPosition: $scrollPosition,
                isActive: isActive,
                isSplit: isSplit,
                isFocused: isFocused,
                hasLeftNeighbor: hasLeftNeighbor,
                hasRightNeighbor: hasRightNeighbor,
                onDrop: onDrop,
                onScaleChange: { scale = $0 },
                onFocus: onFocus
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
        case .markdown(_, let name, _):
            Text(name)
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(.regularMaterial).cornerRadius(4).padding(8)
                .allowsHitTesting(false)
        case .image(_, let name, _):
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
    var isActive: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tab.panes.indices, id: \.self) { i in
                UnifiedPane(
                    content: $tab.panes[i],
                    scrollPosition: $tab.scrollPositions[i],
                    isActive: isActive,
                    isSplit: tab.isSplit,
                    // Hidden tabs stay mounted to preserve their native view
                    // state, but only the selected tab may install focus/key
                    // handling.
                    isFocused: isActive && tab.focusedPane == i,
                    hasLeftNeighbor: i > 0,
                    hasRightNeighbor: i < tab.panes.count - 1,
                    onDrop: { url, side in handleDrop(url: url, paneIndex: i, side: side) },
                    onFocus: { tab.focusedPane = i },
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
                tab.replacePane(at: paneIndex, with: newContent)
                tab.focusedPane = paneIndex
            case .left:
                tab.insertPane(newContent, at: paneIndex)
                tab.focusedPane = paneIndex
            case .right:
                tab.insertPane(newContent, at: paneIndex + 1)
                tab.focusedPane = paneIndex + 1
            }
        }
    }

    private func closePane(at index: Int) {
        guard tab.panes.count > 1 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            tab.removePane(at: index)
            tab.clampFocus()
        }
    }
}
