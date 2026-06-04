import AppKit

/// Plays the meditation bell that bookends a timed session. The sound ships in the app
/// bundle as `Resources/bell.aifc` (copied in by the Makefile's `assemble` step).
///
/// If the file is missing — e.g. running the bare executable outside a built `.app` — we
/// load nil and `ring()` becomes a silent no-op rather than a crash.
final class SessionBell {
    private let sound: NSSound?

    init() {
        if let url = Bundle.main.url(forResource: "bell", withExtension: "aifc") {
            // byReference: don't slurp the file into memory; play it straight from disk.
            sound = NSSound(contentsOf: url, byReference: true)
        } else {
            sound = nil
        }
    }

    /// Rings the bell from the top, cutting off any still-ringing previous play.
    func ring() {
        sound?.stop()
        sound?.play()
    }
}
