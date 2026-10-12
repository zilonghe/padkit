import AppKit
import Combine

/// Gesture recorder + keyboard-shortcut recorder used by the settings window.
@MainActor
final class Recorder: ObservableObject {
    static let timeout = 8

    // gesture recording
    @Published private(set) var isRecordingGesture = false
    @Published private(set) var lastGesture: Gesture?
    @Published private(set) var gestureTimedOut = false

    // shortcut recording: which gesture's shortcut is being captured
    @Published private(set) var shortcutTarget: Gesture?

    @Published private(set) var secondsLeft = 0

    private var countdown: Task<Void, Never>?
    private var keyMonitor: Any?
    private var onShortcut: ((String) -> Void)?

    // MARK: gesture

    func startGesture() {
        cancelShortcut()
        lastGesture = nil
        gestureTimedOut = false
        isRecordingGesture = true
        ClickInterceptor.shared.setRecording(true)
        startCountdown { [weak self] in
            self?.gestureTimedOut = true
            self?.stopGesture()
        }
    }

    func didDetect(_ g: Gesture) {
        guard isRecordingGesture else { return }
        lastGesture = g
        stopGesture()
    }

    func stopGesture() {
        isRecordingGesture = false
        ClickInterceptor.shared.setRecording(false)
        stopCountdown()
    }

    func clearGesture() { lastGesture = nil; gestureTimedOut = false }

    // MARK: shortcut

    func startShortcut(for g: Gesture, onCapture: @escaping (String) -> Void) {
        stopGesture()
        cancelShortcut()
        shortcutTarget = g
        onShortcut = onCapture
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            self?.handleKey(code: code, flags: flags)
            return nil   // swallow the key while recording
        }
        startCountdown { [weak self] in self?.cancelShortcut() }
    }

    func cancelShortcut() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        onShortcut = nil
        if shortcutTarget != nil { shortcutTarget = nil; stopCountdown() }
    }

    private func handleKey(code: UInt16, flags: NSEvent.ModifierFlags) {
        guard shortcutTarget != nil else { return }
        let mods: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        // plain Esc cancels
        if code == 0x35 && flags.intersection(mods).isEmpty { cancelShortcut(); return }
        guard let s = Shortcut.string(keyCode: CGKeyCode(code), flags: flags) else { NSSound.beep(); return }
        let cb = onShortcut
        cancelShortcut()
        cb?(s)
    }

    // MARK: countdown

    private func startCountdown(onExpire: @escaping @MainActor () -> Void) {
        stopCountdown()
        secondsLeft = Recorder.timeout
        countdown = Task { @MainActor [weak self] in
            while let self = self, self.secondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self.secondsLeft -= 1
            }
            if Task.isCancelled { return }
            onExpire()
        }
    }

    private func stopCountdown() {
        countdown?.cancel()
        countdown = nil
        secondsLeft = 0
    }
}

extension Shortcut {
    static let preferredNames: [CGKeyCode: String] = {
        var r: [CGKeyCode: String] = [:]
        for (k, v) in keyCodes where r[v] == nil || k.count > (r[v]?.count ?? 0) { r[v] = k }
        r[0x24] = "return"; r[0x33] = "delete"; r[0x35] = "escape"
        return r
    }()

    static let fnImplicitKeys: Set<CGKeyCode> = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F,
                                                  0x73, 0x77, 0x74, 0x79, 0x75, 0x7B, 0x7C, 0x7D, 0x7E]

    /// Inverse of `parse`: builds e.g. "ctrl+opt+shift+cmd+t".
    static func string(keyCode: CGKeyCode, flags: NSEvent.ModifierFlags) -> String? {
        guard let key = preferredNames[keyCode] else { return nil }
        var parts: [String] = []
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.function) && !fnImplicitKeys.contains(keyCode) { parts.append("fn") }
        parts.append(key)
        return parts.joined(separator: "+")
    }
}
