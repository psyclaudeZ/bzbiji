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
        }
    }
}
