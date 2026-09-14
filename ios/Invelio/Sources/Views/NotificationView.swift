import SwiftUI

struct NotificationView: View {
    var body: some View {
        NavigationStack {
            List {
                Text("Alerts coming soon")
            }
            .navigationTitle("Alerts")
        }
    }
}

#Preview {
    NotificationView()
}
