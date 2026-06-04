import Foundation
import Combine
import CoreGraphics

/// Drives the record/stop lifecycle and bridges the key tap to the database.
///
/// While recording, keystrokes accumulate in memory (`liveTotals` for display,
/// `pending` as the not-yet-persisted delta) and are flushed to SQLite on a timer and
/// on session end — so we get one small write every few seconds instead of one per key.
@MainActor
final class SessionManager: ObservableObject {
    /// True while a session is active and the tap is running.
    @Published private(set) var isRecording = false
    /// Live backspace count for the current session (resets when a new session starts).
    @Published private(set) var backspaceCount = 0
    /// Total keystrokes seen this session (all keys), for the accuracy calc.
    @Published private(set) var totalKeystrokes = 0

    /// Non-backspace presses this session — the counterpart to `backspaceCount`.
    var otherCount: Int { totalKeystrokes - backspaceCount }

    /// Length (in characters) of the streak currently in progress. A streak is a run
    /// of non-backspace presses; it ends the moment backspace is hit and the next one
    /// begins immediately.
    @Published private(set) var currentStreak = 0
    /// Best streak set *within this session* (count + how long it lasted).
    @Published private(set) var sessionLongestCount = 0
    private var sessionLongestDuration: TimeInterval = 0
    /// Best streak from prior sessions, loaded from the DB when recording starts.
    private var historicalLongestCount = 0
    private var historicalLongestDuration: TimeInterval = 0
    /// When the in-progress streak's first character landed (`nil` between streaks).
    private var currentStreakStart: Date?
    /// When the current session began, for the WPM rate.
    private var sessionStart: Date?
    /// For a timed session, its intended length; nil for a free-form session. When set,
    /// the session auto-stops once this elapses, and the bell rings at both ends.
    private var targetDuration: TimeInterval?

    /// The bell that bookends a timed session.
    private let bell = SessionBell()
    /// Whether bells are enabled (mutable from the menu's mute toggle). Read live so a
    /// mid-session toggle takes effect immediately.
    private var bellEnabled: Bool { UserDefaults.standard.bool(forKey: PrefKey.playSessionBell) }

    /// Words per minute, using the convention that a "word" is 5 characters. Counts
    /// non-backspace presses only (backspaces are corrections, not content) over the
    /// wall-clock time since the session started.
    var wpm: Double {
        guard let start = sessionStart else { return 0 }
        let minutes = now.timeIntervalSince(start) / 60
        guard minutes > 0 else { return 0 }
        return (Double(otherCount) / 5) / minutes
    }
    /// Updated once a second while recording so the live duration display ticks.
    @Published private(set) var now = Date()
    private var uiTimer: Timer?

    /// For a timed session, seconds left until it auto-stops; nil for free-form. Recomputed
    /// each second because `now` is published, so the menu's countdown ticks for free.
    var timeRemaining: TimeInterval? {
        guard let target = targetDuration, let start = sessionStart else { return nil }
        return max(0, target - now.timeIntervalSince(start))
    }

    /// Live duration of the in-progress streak.
    var currentStreakDuration: TimeInterval {
        guard let start = currentStreakStart else { return 0 }
        return now.timeIntervalSince(start)
    }
    /// Longest streak to display: the better of this session and all prior ones.
    var longestStreak: Int { max(sessionLongestCount, historicalLongestCount) }
    var longestStreakDuration: TimeInterval {
        sessionLongestCount >= historicalLongestCount ? sessionLongestDuration : historicalLongestDuration
    }

    /// "Accuracy" = percentage of keystrokes that are *not* backspace, for the current
    /// session. `nil` when idle or before any keys arrive (nothing to show yet).
    var accuracy: Double? {
        guard isRecording, totalKeystrokes > 0 else { return nil }
        let good = totalKeystrokes - backspaceCount
        return Double(good) / Double(totalKeystrokes) * 100
    }
    /// Set when the user tried to start but Input Monitoring isn't granted yet.
    @Published var needsPermission = false

    private let db: Database
    private var tap: KeyTap!

    private var currentSessionID: Int64?
    /// Cumulative counts for the current session, kept for live UI display.
    private var liveTotals: [KeyKind: Int] = [:]
    /// Counts observed since the last flush; cleared on each flush.
    private var pending: [KeyKind: Int] = [:]
    private var flushTimer: Timer?

    private let flushInterval: TimeInterval = 5

    init(db: Database) {
        self.db = db
        self.tap = KeyTap { [weak self] keycode, flags in
            // Tap callback runs on the main thread (see KeyTap), so we're already on
            // the main actor — just not statically provably so.
            MainActor.assumeIsolated { self?.record(keycode, flags: flags) }
        }
    }

    // MARK: - Lifecycle

    /// Starts recording. Pass `targetDuration` (in seconds) for a timed session that rings
    /// the bell at both ends and auto-stops when the time is up; omit it for free-form.
    func startSession(targetDuration: TimeInterval? = nil) {
        guard !isRecording else { return }

        guard tap.hasPermission else {
            needsPermission = true
            tap.requestPermission()
            return
        }
        needsPermission = false

        self.targetDuration = targetDuration
        do {
            currentSessionID = try db.startSession(targetSeconds: targetDuration.map { Int($0) })
        } catch {
            NSLog("typesati: failed to start session: \(error)")
            return
        }

        liveTotals.removeAll()
        pending.removeAll()
        backspaceCount = 0
        totalKeystrokes = 0

        currentStreak = 0
        currentStreakStart = nil
        sessionLongestCount = 0
        sessionLongestDuration = 0
        now = Date()
        sessionStart = now
        let allTime = (try? db.allTimeLongestStreak()) ?? (count: 0, duration: 0)
        historicalLongestCount = allTime.count
        historicalLongestDuration = allTime.duration

        guard tap.start() else {
            NSLog("typesati: failed to start key tap")
            return
        }

        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                // A timed session ends itself once its target elapses. Calling endSession
                // from inside the timer's own fire is safe — it invalidates the timer. The
                // closing bell rings here, on *natural* completion only — never when the
                // user ends the session early via the menu.
                if let target = self.targetDuration, let start = self.sessionStart,
                   self.now.timeIntervalSince(start) >= target {
                    if self.bellEnabled { self.bell.ring() }
                    self.endSession()
                }
            }
        }
        isRecording = true
        // Ring the opening bell only for a timed (meditation-style) session, unless muted.
        if targetDuration != nil, bellEnabled { bell.ring() }
    }

    func endSession() {
        guard isRecording, let sessionID = currentSessionID else { return }

        tap.stop()
        flushTimer?.invalidate()
        flushTimer = nil
        uiTimer?.invalidate()
        uiTimer = nil

        // Bank the streak that was in progress when recording stopped.
        finalizeStreak()
        flush()
        do {
            try db.endSession(sessionID)
        } catch {
            NSLog("typesati: failed to end session: \(error)")
        }

        currentSessionID = nil
        isRecording = false
        targetDuration = nil
    }

    // MARK: - Recording

    private func record(_ keycode: Int64, flags: CGEventFlags) {
        // Classify and discard the keycode immediately: from here on we only ever
        // deal in backspace-vs-other, never the actual key.
        let kind = KeyKind(keycode: keycode)
        // Drop word/line deletes (Option/Command + Backspace) entirely — see
        // `isModifiedBackspace`. They're navigation, not a single-character correction.
        if kind.isModifiedBackspace(flags: flags) { return }
        pending[kind, default: 0] += 1
        liveTotals[kind, default: 0] += 1
        totalKeystrokes += 1
        switch kind {
        case .backspace:
            backspaceCount = liveTotals[.backspace] ?? 0
            finalizeStreak()
        case .other:
            if currentStreak == 0 { currentStreakStart = Date() }
            currentStreak += 1
        }
    }

    /// Closes off the in-progress streak: logs it (every streak is persisted, since the
    /// distribution of streak lengths is the improvement signal), updates the in-memory
    /// session best for the live UI, then resets so the next streak starts clean.
    private func finalizeStreak() {
        let length = currentStreak
        let duration = currentStreakStart.map { Date().timeIntervalSince($0) } ?? 0
        defer {
            currentStreak = 0
            currentStreakStart = nil
        }
        // A zero-length "streak" (e.g. backspace before any other key) isn't a run.
        guard length > 0 else { return }
        if length > sessionLongestCount {
            sessionLongestCount = length
            sessionLongestDuration = duration
        }
        guard let sessionID = currentSessionID else { return }
        do {
            try db.recordStreak(sessionID: sessionID, length: length, duration: duration)
        } catch {
            NSLog("typesati: failed to persist streak: \(error)")
        }
    }

    private func flush() {
        guard let sessionID = currentSessionID, !pending.isEmpty else { return }
        let deltas = pending
        pending.removeAll()
        do {
            try db.incrementCounts(sessionID: sessionID, deltas: deltas)
        } catch {
            // Put the deltas back so they're retried on the next flush.
            for (k, v) in deltas { pending[k, default: 0] += v }
            NSLog("typesati: flush failed: \(error)")
        }
    }
}
