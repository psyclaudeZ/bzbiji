import SwiftUI

// MARK: - State persistence

private struct SavedState: Codable {
    var tabNames: [String]
    var tabPaneURLs: [[String?]]   // per-tab, per-pane; nil = empty pane
    var selected: Int
}

private let stateKey = "bzbiji.savedState"

private func saveTabState(_ tabs: TabManager) {
    let state = SavedState(
        tabNames: tabs.names,
        tabPaneURLs: tabs.contents.map { tab in tab.panes.map { $0.sourceURL?.absoluteString } },
        selected: tabs.selected
    )
    if let data = try? JSONEncoder().encode(state) {
        UserDefaults.standard.set(data, forKey: stateKey)
    }
}

private func restoreTabState() -> TabManager? {
    guard let data = UserDefaults.standard.data(forKey: stateKey),
          let state = try? JSONDecoder().decode(SavedState.self, from: data),
          !state.tabNames.isEmpty else { return nil }

    var manager = TabManager(names: state.tabNames)
    manager.selected = min(state.selected, state.tabNames.count - 1)

    for (i, urlStrings) in state.tabPaneURLs.enumerated() {
        guard i < manager.contents.count else { break }
        let panes: [PaneContent] = urlStrings.map { s in
            guard let s, let url = URL(string: s) else { return .empty }
            return PaneContent(url: url) ?? .empty
        }
        if !panes.isEmpty { manager.contents[i].panes = panes }
    }

    return manager
}

// MARK: - Tab bar

private struct TabBar: View {
    @Binding var selected: Int
    @Binding var names: [String]
    @Binding var editingTab: Int?
    let onAdd: () -> Void
    let onClose: (Int) -> Void
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(spacing: 1) {
            ForEach(names.indices, id: \.self) { i in
                tabButton(i)
            }

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: editFocused) { focused in
            if !focused { editingTab = nil }
        }
    }

    private func tabButton(_ i: Int) -> some View {
        Button { selected = i } label: {
            HStack(spacing: 5) {
                if editingTab == i {
                    TextField("", text: $names[i])
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .fixedSize()
                        .focused($editFocused)
                        .onSubmit { editingTab = nil }
                        .onExitCommand { editingTab = nil }
                        .onAppear { editFocused = true }
                        .simultaneousGesture(TapGesture().onEnded { })
                } else {
                    Text(names[i])
                        .font(.system(size: 13))
                }

                if i < 9 {
                    Text("⌘\(i + 1)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
            }
            .foregroundColor(selected == i ? .primary : .secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                selected == i
                    ? Color(NSColor.controlBackgroundColor)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") { selected = i; editingTab = i }
            if names.count > 1 {
                Divider()
                Button("Close Tab") { onClose(i) }
            }
        }
    }
}

// MARK: - Help state (reference type so monitor closure can read/write it)

private class HelpState: ObservableObject {
    @Published var isShowing = false
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 && self.isShowing {
                DispatchQueue.main.async { self.isShowing = false }
                return nil
            }
            return event
        }
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}

// MARK: - Help overlay

private struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(description)
                .foregroundColor(.primary)
            Spacer()
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

private struct HelpOverlay: View {
    @ObservedObject var state: HelpState

    private let sections: [(String, [(String, String)])] = [
        ("Tabs", [
            ("New tab",          "⌘T"),
            ("Close tab",        "⌘W"),
            ("Restore closed tab", "⌘⇧T"),
            ("Rename tab",       "⌘R"),
            ("Next tab",         "⌘⇧D  /  ⌘]"),
            ("Previous tab",     "⌘⇧A  /  ⌘["),
            ("Switch to tab N",  "⌘1 – ⌘8"),
            ("Last tab",         "⌘9"),
        ]),
        ("Image pane", [
            ("Zoom in / out",    "⌘ + scroll"),
            ("Pan",              "Scroll / drag"),
            ("Rotate",           "Two-finger rotate"),
            ("Reset view",       "Double-click"),
        ]),
        ("bzbiji", [
            ("Open file",          "⌘O"),
            ("Open to the right",  "⌘\\"),
            ("Keyboard shortcuts", "⌘?"),
            ("Quit",               "⌘Q"),
        ]),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { state.isShowing = false }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Keyboard Shortcuts")
                        .font(.headline)
                    Spacer()
                    Button { state.isShowing = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(sections, id: \.0) { title, rows in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                                ForEach(rows, id: \.0) { row in
                                    ShortcutRow(keys: row.1, description: row.0)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial)
            .cornerRadius(12)
            .shadow(radius: 20)
        }
    }
}

// MARK: - Content view

struct ContentView: View {
    @State private var tabs = TabManager()
    @State private var editingTab: Int? = nil
    @StateObject private var helpState = HelpState()

    private func openFile(side: DropSide = .center) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let content = PaneContent(url: url) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            switch side {
            case .center:
                tabs.contents[tabs.selected].panes[0] = content
            case .right:
                tabs.contents[tabs.selected].panes.append(content)
            case .left:
                tabs.contents[tabs.selected].panes.insert(content, at: 0)
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabBar(
                    selected: $tabs.selected,
                    names: $tabs.names,
                    editingTab: $editingTab,
                    onAdd: { tabs.addTab() },
                    onClose: { tabs.closeTab(at: $0) }
                )
                Divider()

                TabPaneContainer(tab: $tabs.contents[tabs.selected])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Hidden shortcut buttons
            .background(
                HStack(spacing: 0) {
                    ForEach(tabs.names.indices, id: \.self) { i in
                        if i < 8 {
                            Button("") { tabs.selected = min(i, tabs.count - 1) }
                                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                        }
                    }
                    Button("") { tabs.selectLast() }
                        .keyboardShortcut("9", modifiers: .command)
                    Button("") { tabs.addTab() }
                        .keyboardShortcut("t", modifiers: .command)
                    Button("") { tabs.closeSelected() }
                        .keyboardShortcut("w", modifiers: .command)
                    Button("") { tabs.selectPrev() }
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                    Button("") { tabs.selectNext() }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                    Button("") { tabs.selectPrev() }
                        .keyboardShortcut("{", modifiers: .command)
                    Button("") { tabs.selectNext() }
                        .keyboardShortcut("}", modifiers: .command)
                    Button("") { helpState.isShowing.toggle() }
                        .keyboardShortcut("/", modifiers: .command)
                    Button("") { editingTab = tabs.selected }
                        .keyboardShortcut("r", modifiers: .command)
                    Button("") { tabs.restoreLastClosed() }
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                    Button("") { openFile(side: .center) }
                        .keyboardShortcut("o", modifiers: .command)
                    Button("") { openFile(side: .right) }
                        .keyboardShortcut("\\", modifiers: .command)
                }
                .opacity(0).frame(width: 0, height: 0).clipped()
            )

            if helpState.isShowing {
                HelpOverlay(state: helpState)
            }
        }
        .onAppear {
            if let restored = restoreTabState() { tabs = restored }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveTabState(tabs)
        }
    }
}
