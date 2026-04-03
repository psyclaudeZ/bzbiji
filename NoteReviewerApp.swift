import SwiftUI

@main
struct NoteReviewerApp: App {
    var body: some Scene {
        WindowGroup("Note Reviewer") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appTermination) {
                Button("Quit Note Reviewer") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
