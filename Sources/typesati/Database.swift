import Foundation
import GRDB

/// Owns the SQLite database and all persistence.
///
/// Schema:
///   sessions(id, started_at, ended_at, label, target_seconds)
///   key_counts(session_id, kind, count)  -- PK(session_id, kind), kind in {backspace, other}
///   streaks(id, session_id, length, duration_ms)
///
/// `started_at` / `ended_at` are wall-clock timestamps bracketing each session. We keep
/// session-level start/stop times (the calendar day and the duration both fall out of
/// them), but the privacy line holds *below* the session: nothing records when within a
/// session any individual key was pressed.
///
/// Every streak is logged in `streaks` — one row per run of non-backspace presses, with
/// its `length` (characters) and `duration_ms`. A streak ends on a backspace, so more
/// (shorter) streaks means more corrections: the streak distribution is the core
/// improvement signal, and the all-time best is just the longest row. A streak is
/// ordered/timed, so it can't be reconstructed from the order-free `key_counts`
/// aggregates and has to be persisted explicitly.
///
/// We only ever store two counts per session — backspace presses and everything-else
/// presses — never per-key counts, key order, timing, or the characters produced.
/// That's a deliberate privacy choice: the data can answer "how often did I hit
/// backspace" while holding nothing that could reconstruct what was typed.
final class Database {
    private let dbQueue: DatabaseQueue

    /// `~/Library/Application Support/typesati/`
    static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("typesati", isDirectory: true)
    }

    static var fileURL: URL {
        folderURL.appendingPathComponent("typesati.sqlite")
    }

    /// Opens (creating if needed) the database at `path` and runs migrations. Pass a
    /// temp or `":memory:"` path in tests to inspect the schema in isolation.
    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    convenience init() throws {
        try FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        try self.init(path: Self.fileURL.path)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // Single migration that builds the final schema directly. `key_counts` only ever
        // distinguishes backspace-vs-other (`kind`); we never store the raw keycode, so by
        // design nothing on disk can reconstruct what was typed. The name stays "v1" so
        // databases created before the migrations were squashed see it as already applied
        // and keep their data rather than re-running schema creation.
        migrator.registerMigration("v1") { db in
            try db.create(table: "sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("label", .text)
                // Intended length for a timed session (e.g. 300 = a 5-minute run); null
                // for free-form. Lets us tell "ran the full 5m" from "stopped early".
                t.column("target_seconds", .integer)
            }
            try db.create(table: "key_counts") { t in
                t.column("session_id", .integer).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("count", .integer).notNull().defaults(to: 0)
                t.primaryKey(["session_id", "kind"])
            }
            try db.create(table: "streaks") { t in
                t.autoIncrementedPrimaryKey("id")
                // Each streak belongs to a session; drop them with their session.
                t.column("session_id", .integer).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("length", .integer).notNull()
                t.column("duration_ms", .integer).notNull()
            }
        }
        return migrator
    }

    // MARK: - Session lifecycle

    /// Inserts a new open session (stamped with the start time) and returns its row id.
    /// `targetSeconds` records a timed session's intended length; pass nil for free-form.
    func startSession(label: String? = nil, targetSeconds: Int? = nil) throws -> Int64 {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO sessions (started_at, label, target_seconds) VALUES (?, ?, ?)",
                arguments: [Date(), label, targetSeconds]
            )
            return db.lastInsertedRowID
        }
    }

    /// Stamps `ended_at` on the given session.
    func endSession(_ sessionID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE sessions SET ended_at = ? WHERE id = ?",
                arguments: [Date(), sessionID]
            )
        }
    }

    // MARK: - Streaks

    /// The best (longest) streak ever recorded across all sessions: its character
    /// count and how long it lasted. Returns `(0, 0)` when there's no history yet.
    func allTimeLongestStreak() throws -> (count: Int, duration: TimeInterval) {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT length, duration_ms
                FROM streaks
                ORDER BY length DESC
                LIMIT 1
                """)
            guard let row else { return (0, 0) }
            let count: Int = row["length"]
            let ms: Int = row["duration_ms"]
            return (count, TimeInterval(ms) / 1000)
        }
    }

    /// Appends one finished streak to the log, tied to its session: its length
    /// (non-backspace characters) and how long it lasted. Called as each streak ends, so
    /// the run survives a crash mid-session.
    func recordStreak(sessionID: Int64, length: Int, duration: TimeInterval) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO streaks (session_id, length, duration_ms) VALUES (?, ?, ?)",
                arguments: [sessionID, length, Int(duration * 1000)]
            )
        }
    }

    // MARK: - Counts

    /// Adds a batch of kind deltas to a session's counts in one transaction.
    /// `deltas` maps key kind (backspace/other) -> presses observed since the last flush.
    func incrementCounts(sessionID: Int64, deltas: [KeyKind: Int]) throws {
        guard !deltas.isEmpty else { return }
        try dbQueue.write { db in
            for (kind, delta) in deltas where delta != 0 {
                try db.execute(
                    sql: """
                    INSERT INTO key_counts (session_id, kind, count)
                    VALUES (?, ?, ?)
                    ON CONFLICT(session_id, kind)
                    DO UPDATE SET count = count + excluded.count
                    """,
                    arguments: [sessionID, kind.rawValue, delta]
                )
            }
        }
    }

    // MARK: - Introspection

    /// Column names of every app table, keyed by table name (SQLite/migration bookkeeping
    /// excluded). Exposed so tests can assert the schema never grows a column capable of
    /// identifying an individual key or character — the privacy invariant, enforced.
    func tableColumns() throws -> [String: [String]] {
        try dbQueue.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'grdb_migrations'
                """)
            return try tables.reduce(into: [:]) { acc, table in
                acc[table] = try db.columns(in: table).map(\.name)
            }
        }
    }
}
