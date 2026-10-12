import Foundation
import CoreGraphics

private func clickTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    return ClickInterceptor.shared.handle(type: type, event: event)
}

/// Turns a physical trackpad click made while 3/4 fingers rest on the pad into click3/click4,
/// swallowing the original left-click when that gesture is mapped.
final class ClickInterceptor: @unchecked Sendable {
    static let shared = ClickInterceptor()

    weak var recognizer: GestureRecognizer?
    var onGesture: (@Sendable (Gesture) -> Void)?

    private let lock = NSLock()
    private var enabled = true
    private var mapped: Set<Gesture> = []
    private var swallowUp = false
    private var recording = false
    private var tap: CFMachPort?

    var isRunning: Bool { tap != nil }

    func setRecording(_ on: Bool) {
        lock.lock(); recording = on; lock.unlock()
    }

    func update(enabled: Bool, mapped: Set<Gesture>) {
        lock.lock(); self.enabled = enabled; self.mapped = mapped; lock.unlock()
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: clickTapCallback, userInfo: nil) else {
            return false
        }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
        case .leftMouseDown:
            let n = recognizer?.fingerCount ?? 0
            let g: Gesture? = n == 3 ? .click3 : (n == 4 ? .click4 : nil)
            lock.lock()
            let hit = g.map { recording || (enabled && mapped.contains($0)) } ?? false
            if hit { swallowUp = true }
            lock.unlock()
            if hit, let g = g {
                recognizer?.markConsumed()
                onGesture?(g)
                return nil
            }
        case .leftMouseUp:
            lock.lock()
            let swallow = swallowUp
            swallowUp = false
            lock.unlock()
            if swallow { return nil }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
