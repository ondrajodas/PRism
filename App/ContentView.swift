import SwiftUI

/// Prázdné hlavní okno. Obsah přibude s vlastními issues — seznam PR, diff, nálezy.
struct ContentView: View {
    var body: some View {
        ContentUnavailableView(
            "GitHub PR Review",
            systemImage: "checklist",
            description: Text("Seznam PR se sem doplní v dalších fázích.")
        )
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
