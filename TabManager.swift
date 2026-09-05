import AppKit

// MARK: - Pane content

enum PaneContent {
    case empty
    case markdown(content: String, fileName: String, url: URL)
    case image(image: NSImage, fileName: String, url: URL)

    var isEmpty: Bool { if case .empty = self { return true }; return false }

    var sourceURL: URL? {
        switch self {
        case .empty:                         return nil
        case .markdown(_, _, let url):       return url
        case .image(_, _, let url):          return url
        }
    }

    /// Load from a file URL (md or image). Returns nil for unsupported types.
    init?(url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["md", "markdown"].contains(ext) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            self = .markdown(content: text, fileName: url.lastPathComponent, url: url)
        } else if ["png","jpg","jpeg","webp","gif","tiff","heic"].contains(ext) {
            guard let img = NSImage(contentsOf: url) else { return nil }
            self = .image(image: img, fileName: url.lastPathComponent, url: url)
        } else { return nil }
    }
}

extension PaneContent: Equatable {
    static func == (lhs: PaneContent, rhs: PaneContent) -> Bool {
        switch (lhs, rhs) {
        case (.empty, .empty):                                  return true
        case (.markdown(let a, _, _), .markdown(let b, _, _)): return a == b
        case (.image(let a, _, _), .image(let b, _, _)):       return a === b
        default:                                                return false
        }
    }
}

// MARK: - Per-tab content

struct PaneScrollPosition: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0

    static let zero = PaneScrollPosition()

    var sanitized: PaneScrollPosition {
        PaneScrollPosition(
            x: x.isFinite ? max(0, x) : 0,
            y: y.isFinite ? max(0, y) : 0
        )
    }
}

struct TabContent: Identifiable {
    let id = UUID()
    var panes: [PaneContent] = [.empty]
    var scrollPositions: [PaneScrollPosition] = [.zero]
    var focusedPane: Int = 0
    var isSplit: Bool { panes.count > 1 }

    var hasConsistentPaneState: Bool {
        !panes.isEmpty && panes.count == scrollPositions.count
    }

    mutating func replacePane(at index: Int, with content: PaneContent) {
        guard panes.indices.contains(index) else { return }
        panes[index] = content
        scrollPositions[index] = .zero
    }

    mutating func insertPane(_ content: PaneContent, at index: Int) {
        panes.insert(content, at: index)
        scrollPositions.insert(.zero, at: index)
    }

    @discardableResult
    mutating func removePane(at index: Int) -> PaneContent? {
        guard panes.count > 1, panes.indices.contains(index) else { return nil }
        scrollPositions.remove(at: index)
        return panes.remove(at: index)
    }

    mutating func restorePanes(_ restoredPanes: [PaneContent],
                               scrollPositions restoredPositions: [PaneScrollPosition]) {
        guard !restoredPanes.isEmpty else { return }
        panes = restoredPanes
        scrollPositions = restoredPanes.indices.map { index in
            restoredPositions.indices.contains(index)
                ? restoredPositions[index].sanitized
                : .zero
        }
        clampFocus()
    }

    mutating func clampFocus() {
        focusedPane = min(focusedPane, panes.count - 1)
    }
}

// MARK: - Tab manager (owns all mutable tab state; fully testable)

struct TabManager {
    var names: [String]
    var contents: [TabContent]
    var selected: Int
    private var recentlyClosed: [(name: String, content: TabContent)] = []

    init(names: [String] = ["Tab 1", "Tab 2"]) {
        precondition(!names.isEmpty)
        self.names    = names
        // Construct each tab independently so every tab has a stable, unique
        // identity. SwiftUI uses this identity to keep its pane views alive
        // while another tab is selected.
        self.contents = names.map { _ in TabContent() }
        self.selected = 0
    }

    var count: Int { names.count }
    var canRestoreClosed: Bool { !recentlyClosed.isEmpty }

    /// names.count == contents.count && selected is in bounds
    var isConsistent: Bool {
        names.count == contents.count &&
        selected >= 0 && selected < names.count &&
        contents.allSatisfy(\.hasConsistentPaneState)
    }

    mutating func addTab() {
        names.append("Tab \(names.count + 1)")
        contents.append(TabContent())
        selected = names.count - 1
    }

    mutating func closeTab(at index: Int) {
        guard index >= 0, index < names.count else { return }
        let isLast = names.count == 1
        // Don't archive an already-empty last tab (avoids restoring fresh blanks).
        if !(isLast && contents[index].panes.allSatisfy(\.isEmpty)) {
            recentlyClosed.append((name: names[index], content: contents[index]))
            if recentlyClosed.count > 10 { recentlyClosed.removeFirst() }
        }
        if isLast {
            names[0] = "Tab 1"
            contents[0] = TabContent()
            selected = 0
        } else {
            names.remove(at: index)
            contents.remove(at: index)
            if selected >= names.count { selected = names.count - 1 }
        }
    }

    mutating func closeSelected() { closeTab(at: selected) }

    mutating func restoreLastClosed() {
        guard let last = recentlyClosed.popLast() else { return }
        names.append(last.name)
        contents.append(last.content)
        selected = names.count - 1
    }

    mutating func selectNext() { selected = (selected + 1) % names.count }
    mutating func selectPrev() { selected = selected == 0 ? names.count - 1 : selected - 1 }
    mutating func selectLast() { selected = names.count - 1 }
}
