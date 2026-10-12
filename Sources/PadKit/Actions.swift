import AppKit
import ApplicationServices

@MainActor
enum ActionRunner {
    static func run(_ a: ActionConfig) {
        switch a.type {
        case .none: break
        case .shortcut: Shortcut.send(a.value)
        case .middleClick: middleClick()
        case .launchApp: launch(a.value)
        case .shell: shell(a.value)
        case .snapLeft, .snapRight, .maximize: WindowManager.snap(a.type)
        }
    }

    static func middleClick() {
        let loc = CGEvent(source: nil)?.location ?? .zero
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(mouseEventSource: src, mouseType: .otherMouseDown, mouseCursorPosition: loc, mouseButton: .center)
        let up = CGEvent(mouseEventSource: src, mouseType: .otherMouseUp, mouseCursorPosition: loc, mouseButton: .center)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func launch(_ value: String) {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        var args: [String]
        if v.hasPrefix("/") || v.hasPrefix("~") {
            args = [(v as NSString).expandingTildeInPath]
        } else if NSWorkspace.shared.urlForApplication(withBundleIdentifier: v) != nil {
            args = ["-b", v]
        } else {
            args = ["-a", v]
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = args
        try? p.run()
    }

    static func shell(_ cmd: String) {
        guard !cmd.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", cmd]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { NSLog("PadKit: shell failed \(error)") }
    }
}

enum Shortcut {
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "return": 0x24, "enter": 0x24, "l": 0x25, "j": 0x26,
        "'": 0x27, "k": 0x28, ";": 0x29, "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E,
        ".": 0x2F, "tab": 0x30, "space": 0x31, "`": 0x32, "delete": 0x33, "backspace": 0x33,
        "escape": 0x35, "esc": 0x35,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62,
        "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79, "forwarddelete": 0x75,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]

    /// Parses "cmd+shift+t" style strings.
    static func parse(_ s: String) -> (CGKeyCode, CGEventFlags)? {
        var flags: CGEventFlags = []
        var key: CGKeyCode?
        // allow "+" itself as the key: "cmd++" -> "="? keep simple: split on "+", empty part means "+" not supported
        for raw in s.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch raw {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "fn": flags.insert(.maskSecondaryFn)
            default: key = keyCodes[raw]
            }
        }
        guard let k = key else { return nil }
        return (k, flags)
    }

    static func send(_ s: String) {
        guard let parsed = parse(s) else { NSLog("PadKit: cannot parse shortcut '\(s)'"); return }
        let (code, flags) = parsed
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        var f = flags
        if [0x7B, 0x7C, 0x7D, 0x7E].contains(code) { f.insert(.maskNumericPad); f.insert(.maskSecondaryFn) }
        down?.flags = f
        up?.flags = f
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

@MainActor
enum WindowManager {
    static func snap(_ t: ActionType) {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let r = ref, CFGetTypeID(r) == AXUIElementGetTypeID() else { return }
        let win = r as! AXUIElement

        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let vf = screen.visibleFrame
        // Cocoa (bottom-left origin) -> AX (top-left origin of primary screen)
        var rect = CGRect(x: vf.minX, y: primary.frame.maxY - vf.maxY, width: vf.width, height: vf.height)
        switch t {
        case .snapLeft: rect.size.width = floor(vf.width / 2)
        case .snapRight: rect.size.width = floor(vf.width / 2); rect.origin.x += vf.width - rect.size.width
        default: break
        }
        setFrame(win, rect)
    }

    private static func setFrame(_ win: AXUIElement, _ rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        if let p = AXValueCreate(.cgPoint, &origin) {
            _ = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, p)
        }
        if let s = AXValueCreate(.cgSize, &size) {
            _ = AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, s)
        }
        // set position again: some apps clamp size against the old position
        if let p = AXValueCreate(.cgPoint, &origin) {
            _ = AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, p)
        }
    }
}
