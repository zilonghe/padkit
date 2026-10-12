import Foundation

// Memory layout of a contact as delivered by the private MultitouchSupport.framework.
// Layout follows publicly documented open-source projects (e.g. MiddleClick); stride = 96 bytes.
struct MTPoint { var x: Float; var y: Float }
struct MTVector { var position: MTPoint; var velocity: MTPoint }
struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32        // 1..7: 4 = make touch, 5 = touching, 6 = break touch
    var fingerID: Int32
    var handID: Int32
    var normalized: MTVector // 0...1, origin bottom-left
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTVector
    var zero2a: Int32
    var zero2b: Int32
    var density: Float
}

typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<MTFinger>?, Int32, Double, Int32) -> Int32

private let contactCallback: MTContactCallback = { _, fingers, count, timestamp, _ in
    var list: [MTFinger] = []
    if let fingers = fingers, count > 0 {
        list = Array(UnsafeBufferPointer(start: fingers, count: Int(count)))
    }
    MultitouchManager.shared.onFrame?(list, timestamp)
    return 0
}

/// Loads MultitouchSupport at runtime via dlopen so no private-framework linker flags are needed.
final class MultitouchManager: @unchecked Sendable {
    static let shared = MultitouchManager()

    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private var handle: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var devices: [UnsafeMutableRawPointer] = []

    var onFrame: (@Sendable ([MTFinger], Double) -> Void)?
    var isRunning: Bool { !devices.isEmpty }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        if MemoryLayout<MTFinger>.stride != 96 {
            NSLog("PadKit: unexpected MTFinger stride \(MemoryLayout<MTFinger>.stride)")
        }
        if handle == nil { handle = dlopen(path, RTLD_NOW) }
        guard let h = handle,
              let c = dlsym(h, "MTDeviceCreateList"),
              let r = dlsym(h, "MTRegisterContactFrameCallback"),
              let s = dlsym(h, "MTDeviceStart") else {
            NSLog("PadKit: MultitouchSupport not available")
            return false
        }
        let createList = unsafeBitCast(c, to: CreateListFn.self)
        let register = unsafeBitCast(r, to: RegisterFn.self)
        let startDev = unsafeBitCast(s, to: StartFn.self)
        guard let list = createList()?.takeRetainedValue() else { return false }
        deviceList = list
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: raw)
            register(dev, contactCallback)
            startDev(dev, 0)
            devices.append(dev)
        }
        NSLog("PadKit: started \(devices.count) multitouch device(s)")
        return isRunning
    }

    func stop() {
        guard let h = handle else { return }
        if let u = dlsym(h, "MTUnregisterContactFrameCallback") {
            let unregister = unsafeBitCast(u, to: RegisterFn.self)
            for d in devices { unregister(d, contactCallback) }
        }
        if let s = dlsym(h, "MTDeviceStop") {
            let stopDev = unsafeBitCast(s, to: StopFn.self)
            for d in devices { stopDev(d) }
        }
        devices.removeAll()
        deviceList = nil
    }

    func restart() { stop(); start() }
}
