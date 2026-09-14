import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            PortfolioView()
                .tabItem {
                    Label("Portfolio", systemImage: "chart.pie")
                }

            ChatbotView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }

            NotificationView()
                .tabItem {
                    Label("Alerts", systemImage: "bell")
                }
        }
    }
}

#Preview {
    ContentView()
}
