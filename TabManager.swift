import AppKit

// MARK: - Per-tab content

struct TabContent {
    var markdownContent: String? = nil
    var markdownFileName: String? = nil
    var image: NSImage? = nil
    var imageFileName: String? = nil
    var imageScale: CGFloat = 1.0
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
