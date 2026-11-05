import SwiftData
import SwiftUI

@main
struct Stirling_MoneyApp: App {
    var sharedModelContainer: ModelContainer = {
        #if DEBUG
            // Launch with `-UseSampleData` to review screens with the preview data in memory.
            // The real store on disk is left untouched.
            if ProcessInfo.processInfo.arguments.contains("-UseSampleData") {
                return .preview
            }
        #endif

        let schema = Schema(AppSchema.models)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AccountsView()
        }
        .modelContainer(sharedModelContainer)
    }
}
