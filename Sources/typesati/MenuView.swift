import AppKit
import SwiftUI

/// The menu shown when the menu-bar icon is clicked.
struct MenuView: View {
    @ObservedObject var session: SessionManager
    @AppStorage(PrefKey.showAccuracyInMenuBar) private var showAccuracy = true
    @AppStorage(PrefKey.playSessionBell) private var playSessionBell = true

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
            Button("Start session") { session.startSession() }
        }

        if session.needsPermission {
            Divider()
            Text("Grant “Input Monitoring” in System Settings,")
            Text("then quit and relaunch typesati.")
        }

        Divider()

        Toggle("Show accuracy in menu bar", isOn: $showAccuracy)

        Toggle("Play session bells", isOn: $playSessionBell)

        Button("Open data folder") { openDataFolder() }

        Divider()

        Button("Quit typesati") { NSApplication.shared.terminate(nil) }
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

    /// Reveals the SQLite file in Finder (selecting it inside the typesati folder).
    private func openDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([Database.fileURL])
    }
}
