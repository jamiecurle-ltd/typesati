import Foundation
import CoreGraphics

/// Global keydown listener built on a `CGEventTap` in **listen-only** mode, so it
/// observes keystrokes system-wide without ever intercepting or delaying them.
///
/// Requires the macOS *Input Monitoring* permission (TCC). Use ``hasPermission`` to
/// check and ``requestPermission()`` to prompt the user (which opens System Settings).
final class KeyTap {
    /// Called on the main run loop for every keydown, with the raw virtual keycode and
    /// the modifier flags active at the time of the press.
    private let onKey: (Int64, CGEventFlags) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onKey: @escaping (Int64, CGEventFlags) -> Void) {
        self.onKey = onKey
    }

    /// Whether Input Monitoring has already been granted to this binary.
    var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Prompts for Input Monitoring. Returns true if already granted; otherwise macOS
    /// adds the app to System Settings → Privacy & Security → Input Monitoring and the
    /// user must toggle it on (and usually relaunch the app).
    @discardableResult
    func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    /// Starts observing keydown events. No-op if already running. Returns false if the
    /// tap could not be created (typically missing permission).
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        // Pass `self` through the C callback's refcon (it can't capture context).
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
                tap.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    /// Stops observing and tears down the tap.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - Callback

    private func handle(type: CGEventType, event: CGEvent) {
        // The system can disable a tap if it ever times out; re-enable and move on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown else { return }
        // Ignore auto-repeat: holding a key (e.g. backspace to delete a word) fires a
        // stream of keyDown events. We count intentional presses, so a held key is one
        // keystroke — otherwise backspace-hold wildly inflates counts and tanks accuracy.
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        // The run-loop source lives on the main run loop, so this fires on the main
        // thread; `onKey` can safely touch main-actor state.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        onKey(keycode, event.flags)
    }
}
