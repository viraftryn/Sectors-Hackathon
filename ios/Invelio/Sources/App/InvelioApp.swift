import SwiftUI
import SwiftData

@main
struct InvelioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: HoldingLot.self)
    }
}
