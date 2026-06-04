import Foundation

/// Preference keys for the app. Values live in `UserDefaults` (the standard macOS
/// app-config store), which SwiftUI's `@AppStorage` reads/writes for us — it persists
/// to `~/Library/Preferences/app.typesati.plist` keyed by the bundle id.
///
/// Centralising the key strings here keeps the `@AppStorage` call sites in the App and
/// the menu in sync.
enum PrefKey {
    /// Bool — show the live session accuracy next to the menu-bar icon. Defaults to on
    /// (the `@AppStorage` call sites in the App and menu use `true` as the fallback).
    static let showAccuracyInMenuBar = "showAccuracyInMenuBar"

    /// Bool — ring the bell at the start and natural end of a timed session. Defaults to
    /// on; registered in `TypesatiApp.init` so non-view readers (SessionManager) agree
    /// with the menu toggle instead of seeing a bare-`UserDefaults` false.
    static let playSessionBell = "playSessionBell"
}
