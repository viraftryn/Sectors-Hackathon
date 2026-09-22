import SwiftUI
import SwiftData

@main
struct InvelioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await SupabaseService.shared.registerDevice()
                }
        }
        .modelContainer(for: HoldingLot.self)
    }
}
