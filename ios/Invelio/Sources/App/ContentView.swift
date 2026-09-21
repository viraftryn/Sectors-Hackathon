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
                    Label("Chatbot", systemImage: "bubble.left.and.bubble.right")
                }
        }
    }
}

#Preview {
    ContentView()
}
