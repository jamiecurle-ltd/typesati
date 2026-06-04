import XCTest
import CoreGraphics
@testable import typesati

/// Tests for the privacy-critical classification boundary (`KeyKind`) and the
/// word/line-delete skip rule. These are pure functions, so they need neither the
/// event tap nor the database.
final class KeycodeTests: XCTestCase {

    // MARK: - Classification

    func testBackspaceKeycodeClassifiesAsBackspace() {
        XCTAssertEqual(KeyKind(keycode: Keycode.backspace), .backspace)
        XCTAssertEqual(KeyKind(keycode: 51), .backspace) // kVK_Delete
    }

    func testNonBackspaceKeycodesClassifyAsOther() {
        // A spread of ordinary keys (a, space, return, 0, arrow) all collapse to .other —
        // the app never distinguishes between them.
        for keycode: Int64 in [0, 49, 36, 29, 123] {
            XCTAssertEqual(KeyKind(keycode: keycode), .other, "keycode \(keycode)")
        }
    }

    // MARK: - Modified-backspace skip rule

    func testOptionBackspaceIsDropped() {
        XCTAssertTrue(KeyKind.backspace.isModifiedBackspace(flags: .maskAlternate))
    }

    func testCommandBackspaceIsDropped() {
        XCTAssertTrue(KeyKind.backspace.isModifiedBackspace(flags: .maskCommand))
    }

    func testPlainBackspaceIsKept() {
        XCTAssertFalse(KeyKind.backspace.isModifiedBackspace(flags: []))
    }

    func testShiftBackspaceIsKept() {
        // Only Option/Command turn backspace into a word/line delete; Shift does not.
        XCTAssertFalse(KeyKind.backspace.isModifiedBackspace(flags: .maskShift))
    }

    func testModifiedOtherKeyIsNotDropped() {
        // The rule is backspace-specific: Command+A (select all) must still count.
        XCTAssertFalse(KeyKind.other.isModifiedBackspace(flags: .maskCommand))
        XCTAssertFalse(KeyKind.other.isModifiedBackspace(flags: .maskAlternate))
    }
}
