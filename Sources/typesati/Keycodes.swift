import Foundation
import CoreGraphics

/// Hardware-independent virtual keycodes (Carbon `kVK_*`) we care about by name.
///
/// The numbers come from `<HIToolbox/Events.h>` and are stable across keyboard layouts.
enum Keycode {
    /// `kVK_Delete` — the key labelled "delete"/"backspace" on Mac keyboards.
    static let backspace: Int64 = 51
}

/// The only distinction we ever persist: was a press backspace, or anything else?
///
/// This is the privacy boundary. We classify a raw keycode into a `KeyKind` at the
/// moment we receive it and then throw the keycode away — so nothing downstream
/// (in memory or on disk) ever knows *which* key was pressed, only backspace-vs-not.
/// That's what keeps the database from being a usable record of what was typed.
enum KeyKind: String {
    case backspace
    case other

    init(keycode: Int64) {
        self = keycode == Keycode.backspace ? .backspace : .other
    }

    /// Whether this press should be dropped entirely — neither counted nor allowed to
    /// break the current streak.
    ///
    /// Option/Command + Backspace delete a whole word or line, not a single mistyped
    /// character. We treat those as navigation rather than a correction, so they don't
    /// inflate the backspace count or end a streak the way a real backspace does.
    func isModifiedBackspace(flags: CGEventFlags) -> Bool {
        self == .backspace && (flags.contains(.maskAlternate) || flags.contains(.maskCommand))
    }
}
