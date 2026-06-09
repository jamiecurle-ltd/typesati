import AppKit
import SwiftUI

/// The menu shown when the menu-bar icon is clicked.
struct MenuView: View {
    @ObservedObject var session: SessionManager
    @AppStorage(PrefKey.showAccuracyInMenuBar) private var showAccuracy = true
    @AppStorage(PrefKey.playSessionBell) private var playSessionBell = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if session.isRecording {
            Text("Recording")
            if let remaining = session.timeRemaining {
                Text("time remaining: \(clock(remaining))")
            }
            Text("\(session.backspaceCount) backspace / \(session.otherCount) others")
            Text(
                "current streak: \(session.currentStreak) characters, \(clock(session.currentStreakDuration)) (\(streakWPM(session.currentStreak, session.currentStreakDuration)) wpm)"
            )
            Text(
                "longest streak: \(session.longestStreak) characters, \(clock(session.longestStreakDuration)) (\(streakWPM(session.longestStreak, session.longestStreakDuration)) wpm)"
            )
            Text("words per minute: \(Int(session.wpm.rounded()))")
            Button("End session") { session.endSession() }
        } else {
            Button("Start 5-min session") { session.startSession(targetDuration: 5 * 60) }
            Button("Start an open session") { session.startSession() }
        }

        if session.needsPermission {
            Divider()
            Text("Grant “Input Monitoring” in System Settings,")
            Text("then quit and relaunch typesati.")
        }

        Divider()

        Toggle("Show accuracy in menu bar", isOn: $showAccuracy)

        Toggle("Play session bells", isOn: $playSessionBell)

        Divider()

        Button("Show stats…") { showStats() }

        Button("Open data folder") { openDataFolder() }

        Divider()

        Button("Request a feature…") { requestFeature() }

        Button("What’s new…") { openChangelog() }

        Divider()

        Text("typesati \(appVersion)")

        Button("Quit typesati") { NSApplication.shared.terminate(nil) }
    }

    /// The app's marketing version (`CFBundleShortVersionString`), shown in the menu so the
    /// user can tell at a glance which build they're on. Falls back to "—" if unreadable.
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "v\($0)" } ?? "—"
    }

    /// Formats a duration as `mm:ss` (e.g. 334s -> "05:34").
    private func clock(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// WPM for a single streak: its characters (÷5 = words) over its duration.
    private func streakWPM(_ characters: Int, _ duration: TimeInterval) -> Int {
        guard duration > 0 else { return 0 }
        return Int(((Double(characters) / 5) / (duration / 60)).rounded())
    }

    /// Opens (or brings forward) the stats window. A MenuBarExtra app has no regular
    /// windows by default, so we also activate the app to pull the window in front.
    private func showStats() {
        openWindow(id: "stats")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Reveals the SQLite file in Finder (selecting it inside the typesati folder).
    private func openDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([Database.fileURL])
    }

    /// Opens the public Canny board where users can submit and upvote feature requests.
    private func requestFeature() {
        NSWorkspace.shared.open(URL(string: "https://typesati.canny.io/feature-requests")!)
    }

    /// Opens the public Canny changelog so users can see what's new.
    private func openChangelog() {
        NSWorkspace.shared.open(URL(string: "https://typesati.canny.io/changelog")!)
    }
}
