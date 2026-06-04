import XCTest
@testable import typesati

/// Negative assertions on the persisted schema: proof that the database *cannot* hold
/// data identifying which keys or characters were typed. The classification boundary is
/// covered in `KeycodeTests`; these guard the other end — that a future migration can't
/// quietly reintroduce a keycode/character column without a test going red.
final class PrivacyTests: XCTestCase {

    /// A fresh, isolated in-memory database with the current schema applied.
    private func freshSchema() throws -> [String: [String]] {
        try Database(path: ":memory:").tableColumns()
    }

    /// The schema is exactly the three privacy-reviewed tables — no more. Adding a table
    /// must be a deliberate act that fails this test until the reviewer updates it.
    func testSchemaIsExactlyTheReviewedTables() throws {
        let tables = Set(try freshSchema().keys)
        XCTAssertEqual(tables, ["sessions", "key_counts", "streaks"])
    }

    /// No column on any table is named (or even hints at) a key identity, character, or
    /// glyph. This is the core privacy invariant: the store keeps counts and timings,
    /// never *what* was pressed.
    func testNoColumnCanIdentifyAKeyOrCharacter() throws {
        // Substrings that would betray per-key or per-character storage.
        let forbidden = ["keycode", "char", "glyph", "unicode", "scancode", "keysym", "typed"]
        for (table, columns) in try freshSchema() {
            for column in columns {
                let name = column.lowercased()
                for needle in forbidden {
                    XCTAssertFalse(
                        name.contains(needle),
                        "\(table).\(column) looks like it stores key/character data (matched \"\(needle)\")"
                    )
                }
            }
        }
    }

    /// `key_counts` is the privacy-critical table: pin its columns exactly. The only key
    /// discriminator is `kind` (backspace vs other, a two-value enum) — never a keycode.
    func testKeyCountsStoresOnlyKindAndCount() throws {
        let columns = Set(try XCTUnwrap(try freshSchema()["key_counts"]))
        XCTAssertEqual(columns, ["session_id", "kind", "count"])
    }
}
