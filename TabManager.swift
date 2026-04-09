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

struct TabContent {
    var panes: [PaneContent] = [.empty]
    var focusedPane: Int = 0
    var isSplit: Bool { panes.count > 1 }

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
        self.contents = Array(repeating: TabContent(), count: names.count)
        self.selected = 0
    }

    var count: Int { names.count }
    var canRestoreClosed: Bool { !recentlyClosed.isEmpty }

    /// names.count == contents.count && selected is in bounds
    var isConsistent: Bool {
        names.count == contents.count && selected >= 0 && selected < names.count
    }

    mutating func addTab() {
        names.append("Tab \(names.count + 1)")
        contents.append(TabContent())
        selected = names.count - 1
    }

    mutating func closeTab(at index: Int) {
        guard names.count > 1, index >= 0, index < names.count else { return }
        recentlyClosed.append((name: names[index], content: contents[index]))
        if recentlyClosed.count > 10 { recentlyClosed.removeFirst() }
        names.remove(at: index)
        contents.remove(at: index)
        if selected >= names.count { selected = names.count - 1 }
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
