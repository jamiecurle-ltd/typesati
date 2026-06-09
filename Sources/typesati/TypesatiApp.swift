import SwiftUI
import AppKit

@main
struct TypesatiApp: App {
    @StateObject private var session: SessionManager
    @AppStorage(PrefKey.showAccuracyInMenuBar) private var showAccuracy = true
    /// Kept so the stats window can query history directly (same instance the session writes to).
    private let db: Database

    init() {
        // Defaults that non-view code also reads (SessionManager checks the bell pref), so
        // they can't rely on an `@AppStorage` inline fallback. Register before anything
        // reads them; a stored value the user has set always wins over this.
        UserDefaults.standard.register(defaults: [PrefKey.playSessionBell: true])

        // The DB is essential; if it can't open there's nothing useful to do, so crash
        // loudly with the reason rather than running in a broken state.
        let db: Database
        do {
            db = try Database()
        } catch {
            fatalError("typesati: could not open database: \(error)")
        }
        self.db = db
        _session = StateObject(wrappedValue: SessionManager(db: db))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(session: session)
        } label: {
            // Filled icon while recording gives an at-a-glance status in the menu bar.
            // When the pref is on and a session is live, append the accuracy %.
            let icon = session.isRecording ? "keyboard.fill" : "keyboard"
            if showAccuracy, let accuracy = session.accuracy {
                Text("\(Image(systemName: icon)) \(accuracy, specifier: "%.1f")%")
            } else {
                Image(systemName: icon)
            }
        }

        // Stats live in a regular window, opened from the menu via openWindow(id: "stats").
        Window("typesati: your progress", id: "stats") {
            StatsView(db: db)
        }
        // Fixed-size window: the view sets an exact frame, and .contentSize locks the
        // window to it so there's no resize handle.
        .windowResizability(.contentSize)
    }
}
