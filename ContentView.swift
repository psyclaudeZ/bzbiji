import SwiftUI

struct ContentView: View {
    var body: some View {
        HSplitView {
            MarkdownPane()
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            ImagePane()
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
