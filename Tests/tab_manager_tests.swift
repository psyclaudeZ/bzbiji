// Run with:
//   swiftc -sdk $(xcrun --show-sdk-path --sdk macosx) -target arm64-apple-macosx13.0 \
//     -parse-as-library TabManager.swift MarkdownConverter.swift Tests/tab_manager_tests.swift \
//     -framework AppKit -o .test_runner \
//     && ./.test_runner ; rm -f .test_runner

import Foundation
import AppKit

// MARK: - Minimal test harness

private var failures = 0
private var passed   = 0
private var names: [String] = []

private func expect(_ cond: Bool, _ msg: String,
                    file: String = #file, line: Int = #line) {
    if cond { passed += 1 }
    else {
        let f = URL(fileURLWithPath: file).lastPathComponent
        print("    FAIL \(f):\(line) — \(msg)")
        failures += 1
    }
}

private func eq<T: Equatable>(_ a: T, _ b: T, _ label: String = "",
                               file: String = #file, line: Int = #line) {
    expect(a == b,
           "\(label.isEmpty ? "" : label + ": ")\(a) != \(b)",
           file: file, line: line)
}

private func test(_ name: String, _ body: () -> Void) {
    body()
    names.append(name)
}

// MARK: - Tests

private func runAll() {
    test("initial state") {
        let m = TabManager()
        eq(m.count, 2, "count")
        eq(m.selected, 0, "selected")
        eq(m.names[0], "Tab 1")
        eq(m.names[1], "Tab 2")
        expect(m.isConsistent, "isConsistent")
    }

    test("names and contents always equal length") {
        let m = TabManager()
        eq(m.names.count, m.contents.count, "lengths equal")
    }

    test("tabs have stable unique identities") {
        var m = TabManager()
        let firstID = m.contents[0].id
        expect(m.contents[0].id != m.contents[1].id, "initial tab IDs are unique")
        m.selected = 1
        eq(m.contents[0].id, firstID, "selection preserves identity")
        m.addTab()
        expect(Set(m.contents.map(\.id)).count == m.contents.count, "added tab ID is unique")
    }

    test("pane scroll state stays aligned with pane mutations") {
        var tab = TabContent()
        tab.scrollPositions[0] = PaneScrollPosition(x: 12, y: 345)
        tab.insertPane(.empty, at: 0)
        eq(tab.scrollPositions[0], .zero, "inserted pane starts at top")
        eq(tab.scrollPositions[1], PaneScrollPosition(x: 12, y: 345), "old pane position shifts")
        tab.replacePane(at: 1, with: .empty)
        eq(tab.scrollPositions[1], .zero, "replacement starts at top")
        tab.removePane(at: 0)
        expect(tab.hasConsistentPaneState, "scroll state remains aligned")
    }

    test("restored pane positions are sanitized and padded") {
        var tab = TabContent()
        tab.restorePanes([.empty, .empty], scrollPositions: [
            PaneScrollPosition(x: -4, y: 123)
        ])
        eq(tab.scrollPositions[0], PaneScrollPosition(x: 0, y: 123), "invalid axis clamped")
        eq(tab.scrollPositions[1], .zero, "missing position padded")
        expect(tab.hasConsistentPaneState, "restored state aligned")
    }

    test("nested Markdown lists preserve indentation hierarchy") {
        let markdown = """
        Topics:
        1. Parent
          - Child bullet
            1. Grandchild number
          - Second child
        2. Sibling
        """
        let html = MarkdownConverter.toBodyHTML(markdown)
        let expected = """
        <p>Topics:</p>
        <ol>
        <li>Parent
        <ul>
        <li>Child bullet
        <ol>
        <li>Grandchild number</li>
        </ol>
        </li>
        <li>Second child</li>
        </ul>
        </li>
        <li>Sibling</li>
        </ol>

        """
        eq(html, expected, "nested list HTML")
    }

    test("ordered Markdown lists retain a non-one starting number") {
        let html = MarkdownConverter.toBodyHTML("3. Third\n4. Fourth")
        expect(html.hasPrefix("<ol start=\"3\">"), "ordered-list start retained")
    }

    test("addTab appends and selects new tab") {
        var m = TabManager()
        m.addTab()
        eq(m.count, 3, "count")
        eq(m.selected, 2, "selected")
        eq(m.names[2], "Tab 3", "name")
        eq(m.names.count, m.contents.count, "in sync")
        expect(m.isConsistent, "isConsistent")
    }

    test("multiple addTabs stay in sync") {
        var m = TabManager()
        m.addTab(); m.addTab(); m.addTab()
        eq(m.count, 5)
        eq(m.names.count, m.contents.count, "in sync")
        expect(m.isConsistent, "isConsistent")
    }

    test("closeTab at last index clamps selected") {
        var m = TabManager()
        m.addTab()           // 3 tabs, selected = 2
        m.closeTab(at: 2)
        eq(m.count, 2)
        eq(m.selected, 1, "clamped")
        eq(m.names.count, m.contents.count, "in sync")
        expect(m.isConsistent, "isConsistent")
    }

    test("closeTab at first index shifts selected down") {
        var m = TabManager()
        m.addTab()           // 3 tabs, selected = 2
        m.closeTab(at: 0)
        eq(m.count, 2)
        eq(m.selected, 1, "shifted down")
        eq(m.names.count, m.contents.count, "in sync")
        expect(m.isConsistent, "isConsistent")
    }

    test("closeSelected removes active tab") {
        var m = TabManager()
        m.addTab()           // 3 tabs, selected = 2
        m.selected = 1
        m.closeSelected()
        eq(m.count, 2)
        eq(m.names.count, m.contents.count, "in sync")
        expect(m.isConsistent, "isConsistent")
    }

    test("closing the last tab resets it to a fresh empty tab") {
        var m = TabManager()
        m.closeTab(at: 0)   // 2 → 1
        m.closeTab(at: 0)   // 1 → 1 (reset to fresh)
        eq(m.count, 1, "stays at 1")
        eq(m.names[0], "Tab 1", "renamed back to Tab 1")
        expect(m.contents[0].panes.allSatisfy(\.isEmpty), "panes are empty")
        expect(m.isConsistent, "isConsistent")
    }

    test("selectNext wraps around") {
        var m = TabManager()   // 2 tabs, selected = 0
        m.selectNext(); eq(m.selected, 1)
        m.selectNext(); eq(m.selected, 0, "wrapped")
        expect(m.isConsistent, "isConsistent")
    }

    test("selectPrev wraps around") {
        var m = TabManager()   // 2 tabs, selected = 0
        m.selectPrev(); eq(m.selected, 1, "wrapped to last")
        m.selectPrev(); eq(m.selected, 0)
        expect(m.isConsistent, "isConsistent")
    }

    test("selectLast picks last index") {
        var m = TabManager()
        m.addTab(); m.addTab()   // 4 tabs
        m.selectLast()
        eq(m.selected, 3)
        expect(m.isConsistent, "isConsistent")
    }

    test("restoreLastClosed reopens closed tab") {
        var m = TabManager()
        m.addTab()                      // 3 tabs, selected = 2
        m.names[2] = "Notes"            // give it a recognisable name
        m.closeTab(at: 2)
        eq(m.count, 2)
        m.restoreLastClosed()
        eq(m.count, 3, "restored")
        eq(m.selected, 2, "selects restored tab")
        eq(m.names[2], "Notes", "name preserved")
        eq(m.names.count, m.contents.count, "in sync")
        expect(m.isConsistent, "isConsistent")
    }

    test("restoreLastClosed is no-op when nothing closed") {
        var m = TabManager()
        m.restoreLastClosed()           // nothing to restore
        eq(m.count, 2, "unchanged")
        expect(m.isConsistent, "isConsistent")
    }

    test("canRestoreClosed reflects stack state") {
        var m = TabManager()
        expect(!m.canRestoreClosed, "empty initially")
        m.addTab()
        m.closeTab(at: 2)
        expect(m.canRestoreClosed, "true after close")
        m.restoreLastClosed()
        expect(!m.canRestoreClosed, "empty after restore")
    }

    test("mixed add/close keeps arrays in sync") {
        var m = TabManager()
        for _ in 0..<5 { m.addTab() }
        for _ in 0..<4 { m.closeSelected() }
        eq(m.names.count, m.contents.count, "in sync")
        expect(m.isConsistent, "isConsistent")
    }
}

// MARK: - Entry point

@main struct TestRunner {
    static func main() {
        runAll()

        let bar = String(repeating: "─", count: 44)
        print("TabManager Tests")
        print(bar)
        for name in names { print("  ✓ \(name)") }
        print(bar)
        if failures == 0 {
            print("All \(passed) checks passed.")
        } else {
            print("\(failures) check(s) FAILED, \(passed) passed.")
            exit(1)
        }
    }
}
