import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("Market overview coming soon")
            }
            .navigationTitle("Invelio")
        }
    }
}

#Preview {
    HomeView()
}
