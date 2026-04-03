import SwiftUI

// MARK: - Tab bar

private struct TabBar: View {
    @Binding var selected: Int
    @Binding var names: [String]
    let onAdd: () -> Void
    @State private var editingTab: Int? = nil
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
                Button("Close Tab") {
                    names.remove(at: i)
                    if selected >= names.count { selected = names.count - 1 }
                }
            }
        }
    }
}

// MARK: - Content view

struct ContentView: View {
    @State private var selected = 0
    @State private var tabNames = ["Tab 1", "Tab 2"]

    var body: some View {
        VStack(spacing: 0) {
            TabBar(selected: $selected, names: $tabNames) {
                tabNames.append("Tab \(tabNames.count + 1)")
                selected = tabNames.count - 1
            }
            Divider()

            ZStack {
                ForEach(tabNames.indices, id: \.self) { i in
                    HSplitView {
                        MarkdownPane()
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                        ImagePane()
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selected == i ? 1 : 0)
                    .allowsHitTesting(selected == i)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            HStack(spacing: 0) {
                ForEach(tabNames.indices, id: \.self) { i in
                    if i < 9 {
                        Button("") { selected = i }
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    }
                }
                Button("") {
                    tabNames.append("Tab \(tabNames.count + 1)")
                    selected = tabNames.count - 1
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            .opacity(0).frame(width: 0, height: 0).clipped()
        )
    }
}
