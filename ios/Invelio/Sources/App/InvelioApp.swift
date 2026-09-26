import SwiftUI
import SwiftData

@main
struct InvelioApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashScreenView()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showSplash = false
                                }
                            }
                        }
                }
            }
            .task {
                await HomeDataStore.shared.preloadAll()
            }
        }
        .modelContainer(for: HoldingLot.self)
    }
}
