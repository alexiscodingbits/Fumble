import AppKit
import Carbon.HIToolbox
import CoreGraphics
import FumbleCore
import Foundation

/// The `CGEventTap` that watches keystrokes system-wide, and the provenance checks that
/// decide which of them count as human typing.
///
/// **Read-only by construction.** The tap is created with `.listenOnly`, so this process
/// cannot modify, swallow, or inject events even if it tried. That is enforced by the OS, not
/// by our own discipline.
@MainActor
public final class EventTap {

    public typealias Handler = (KeyEvent) -> Void

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: Handler

    /// Cached so we don't ask `NSWorkspace` for the frontmost app on every keystroke.
    private var frontmostBundleID: String?
    private var activationObserver: NSObjectProtocol?

    public private(set) var isRunning = false
    /// Set when the OS disables our tap (see `tapDisabled`), so the UI can explain the gap.
    public private(set) var wasDisabledByTimeout = false

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    // MARK: - Permission

    /// Input Monitoring, *not* Accessibility. `AXIsProcessTrusted()` reflects the wrong
    /// permission and returns false positives here — a listen-only keyboard tap on macOS
    /// 10.15+ is gated on `kTCCServiceListenEvent`, which these two APIs cover.
    public static var hasPermission: Bool {
        CGPreflightListenEventAccess()
    }

    /// Prompts once. macOS only ever shows this dialog a single time per app identity; after a
    /// denial the user has to go to System Settings, so the UI must offer that route too.
    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    public static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Lifecycle

    public func start() -> Bool {
        guard !isRunning else { return true }
        guard Self.hasPermission else { return false }

        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observeAppActivation()

        // flagsChanged is included so modifier presses break the typing sequence rather than
        // being invisible — otherwise Shift between two letters looks like a direct bigram.
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: unmanagedSelf
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        machPort = port
        runLoopSource = source
        isRunning = true
        return true
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
        }
        runLoopSource = nil
        machPort = nil
        isRunning = false

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func observeAppActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.frontmostBundleID = app?.bundleIdentifier
            }
        }
    }

    /// Re-enables the tap after macOS switches it off.
    ///
    /// The OS kills taps whose callback is too slow (`tapDisabledByTimeout`) and on some
    /// wake-from-sleep transitions. Silently losing capture is the worst possible failure for
    /// this app — the stats would just quietly stop being true — so we always re-arm and
    /// record that it happened.
    fileprivate func handleTapDisabled() {
        wasDisabledByTimeout = true
        reenable()
    }

    /// Re-arm the tap. Idempotent; called on wake because macOS sometimes disables taps across
    /// sleep without delivering a tapDisabled event.
    func reenable() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: true)
        }
    }

    // MARK: - Event classification

    /// The scalars we need from a `CGEvent`, extracted in the tap callback.
    ///
    /// `CGEvent` is a non-`Sendable` reference type, so it must not cross into main-actor
    /// isolation. Reading the fields up front and forwarding this instead keeps the actor
    /// boundary clean — and makes it explicit that the only thing leaving the callback is
    /// four numbers.
    struct RawKeyEvent: Sendable {
        let keyCode: Int
        let isKeyDown: Bool
        let isAutorepeat: Bool
        let isSynthetic: Bool
        let isSecureInput: Bool
        let timestamp: Double
    }

    /// Reads everything needed off the event. Nonisolated: runs wherever the tap callback runs.
    nonisolated static func extract(type: CGEventType, event: CGEvent) -> RawKeyEvent? {
        guard type == .keyDown || type == .flagsChanged else { return nil }
        return RawKeyEvent(
            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
            isKeyDown: type == .keyDown,
            // Autorepeat is only meaningful for keyDown.
            isAutorepeat: type == .keyDown
                && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            isSynthetic: isSynthetic(event),
            // A modifier press cannot itself be secure-field text, and asking the OS is not free.
            isSecureInput: type == .keyDown && IsSecureEventInputEnabled(),
            // `systemUptime` is monotonic and cheap. The CGEvent timestamp is mach absolute
            // time and would need conversion for no benefit at human typing rates.
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    /// Attaches the frontmost app (main-actor state) and hands the event to the recorder.
    ///
    /// A modifier press produces no text, but it is a real discontinuity in the typing stream,
    /// so it is forwarded as a non-typing key rather than dropped — the recorder uses it to
    /// break the sequence.
    fileprivate func process(_ raw: RawKeyEvent) {
        handler(KeyEvent(
            key: KeyIdentity(keyCode: raw.keyCode),
            timestamp: raw.timestamp,
            isAutorepeat: raw.isAutorepeat,
            isSynthetic: raw.isSynthetic,
            isSecureInput: raw.isSecureInput,
            appBundleID: frontmostBundleID
        ))
    }

    /// Distinguishes a human pressing a key from software injecting one.
    ///
    /// This is the mechanism behind honest WPM, and it is worth being precise about what it
    /// does and doesn't catch:
    ///
    /// - **Pastes and most AI completions never appear here at all.** ⌘V is a single keyDown;
    ///   the inserted text arrives via the pasteboard, and editor/LLM completions are inserted
    ///   through the text system. So they cannot inflate our counts in the first place. Any
    ///   tracker reporting 400 WPM is counting something else.
    /// - **What this check does catch** is text *replayed as keystrokes* — text expanders,
    ///   automation (Hammerspoon, Keyboard Maestro, `osascript`), remote-control software, and
    ///   the AI tools that type into the frontmost app rather than using an API. Those post
    ///   real keyDown events and would otherwise count as your own typing.
    ///
    /// Hardware events carry `kCGEventSourceStateHIDSystemState`; anything posted by a process
    /// via `CGEventPost` carries a different source state.
    ///
    /// - Note: This is a strong signal, not a proof — a determined injector can spoof the
    ///   source state. Validating it against real automation tools is the M2 task. Until then
    ///   `rejectedSynthetic` is surfaced in the UI so the filter's behaviour is visible
    ///   rather than assumed.
    nonisolated static func isSynthetic(_ event: CGEvent) -> Bool {
        let stateID = event.getIntegerValueField(.eventSourceStateID)
        return stateID != Int64(CGEventSourceStateID.hidSystemState.rawValue)
    }
}

/// C callback. Runs on the main thread because the run-loop source is attached to the main
/// run loop, which is what makes `assumeIsolated` sound here.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { tap.handleTapDisabled() }
    default:
        // Read the CGEvent's fields here, outside actor isolation, and forward only scalars.
        if let raw = EventTap.extract(type: type, event: event) {
            MainActor.assumeIsolated { tap.process(raw) }
        }
    }

    // Always pass the event through untouched. `.listenOnly` means the return value is
    // ignored, but returning the event unmodified keeps that explicit.
    return Unmanaged.passUnretained(event)
}
