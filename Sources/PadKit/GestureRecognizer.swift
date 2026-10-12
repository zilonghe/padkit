import Foundation

enum Gesture: String, CaseIterable, Codable, Identifiable, Sendable {
    case tap3, tap4, tap5
    case click3, click4
    case swipe3Up, swipe3Down, swipe3Left, swipe3Right
    case swipe4Up, swipe4Down, swipe4Left, swipe4Right
    case tipTapLeft, tipTapRight
    case twoHoldTapLeft, twoHoldTapRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tap3: return "三指轻点"
        case .tap4: return "四指轻点"
        case .tap5: return "五指轻点"
        case .click3: return "三指按压点击"
        case .click4: return "四指按压点击"
        case .swipe3Up: return "三指向上滑"
        case .swipe3Down: return "三指向下滑"
        case .swipe3Left: return "三指向左滑"
        case .swipe3Right: return "三指向右滑"
        case .swipe4Up: return "四指向上滑"
        case .swipe4Down: return "四指向下滑"
        case .swipe4Left: return "四指向左滑"
        case .swipe4Right: return "四指向右滑"
        case .tipTapLeft: return "一指按住·左侧轻点"
        case .tipTapRight: return "一指按住·右侧轻点"
        case .twoHoldTapLeft: return "两指按住·左侧轻点"
        case .twoHoldTapRight: return "两指按住·右侧轻点"
        }
    }
}

/// Clean-room recogniser working on raw contact frames. Thread-safe (frames arrive on a private thread).
final class GestureRecognizer: @unchecked Sendable {
    var onGesture: (@Sendable (Gesture) -> Void)?

    // Tunables (normalized trackpad units / seconds)
    var swipeThreshold: Float = 0.12
    var tapMaxDuration: Double = 0.30
    var tapMaxTravel: Float = 0.04
    var tipTapMaxDuration: Double = 0.30
    var tipTapRestMin: Double = 0.12

    private let lock = NSLock()
    private var count = 0

    // session (first finger down -> all fingers up)
    private var active = false
    private var sessionStart = 0.0
    private var maxCount = 0
    private var consumed = false
    private var maxTravel: Float = 0
    private var firstPos: [Int32: MTPoint] = [:]
    private var swipeBase: MTPoint?
    private var swipeBaseCount = 0

    // tip-tap
    private var restingID: Int32?
    private var restingSince = 0.0
    private var tipID: Int32?
    private var tipStart = 0.0
    private var tipIsLeft = false

    // two-finger hold + third finger tap
    private var holdIDs: Set<Int32> = []
    private var holdSince = 0.0
    private var holdAnchor: [Int32: MTPoint] = [:]
    private var thirdID: Int32?
    private var thirdStart = 0.0
    private var thirdIsLeft = false
    var holdStillMax: Float = 0.03

    var fingerCount: Int { lock.lock(); defer { lock.unlock() }; return count }

    /// Called when a physical click was turned into a gesture, so the touch session is not also reported as a tap.
    func markConsumed() { lock.lock(); consumed = true; lock.unlock() }

    func process(_ fingers: [MTFinger], timestamp ts: Double) {
        var fired: [Gesture] = []
        lock.lock()
        let touching = fingers.filter { $0.state == 4 || $0.state == 5 }
        let n = touching.count
        count = n

        if n == 0 {
            if active {
                let dur = ts - sessionStart
                if !consumed && maxCount >= 3 && dur <= tapMaxDuration && maxTravel <= tapMaxTravel {
                    switch maxCount {
                    case 3: fired.append(.tap3)
                    case 4: fired.append(.tap4)
                    default: fired.append(.tap5)
                    }
                }
            }
            active = false
            restingID = nil
            tipID = nil
            holdIDs = []; holdAnchor = [:]; thirdID = nil
        } else {
            if !active {
                active = true; sessionStart = ts; maxCount = 0; consumed = false
                maxTravel = 0; firstPos = [:]; swipeBase = nil; swipeBaseCount = 0
            }
            for f in touching {
                let p = f.normalized.position
                if let s = firstPos[f.identifier] {
                    maxTravel = max(maxTravel, hypotf(p.x - s.x, p.y - s.y))
                } else {
                    firstPos[f.identifier] = p
                }
            }
            maxCount = max(maxCount, n)

            // Swipes: centroid displacement while exactly 3 or 4 fingers are down.
            if (n == 3 || n == 4) && !consumed {
                let c = centroid(touching)
                if swipeBaseCount != n || swipeBase == nil {
                    swipeBase = c; swipeBaseCount = n
                } else if let b = swipeBase {
                    let dx = c.x - b.x, dy = c.y - b.y
                    if max(abs(dx), abs(dy)) >= swipeThreshold {
                        consumed = true
                        let g: Gesture
                        if abs(dx) > abs(dy) {
                            g = n == 3 ? (dx > 0 ? .swipe3Right : .swipe3Left) : (dx > 0 ? .swipe4Right : .swipe4Left)
                        } else {
                            // normalized y grows upwards
                            g = n == 3 ? (dy > 0 ? .swipe3Up : .swipe3Down) : (dy > 0 ? .swipe4Up : .swipe4Down)
                        }
                        fired.append(g)
                    }
                }
            } else {
                swipeBase = nil; swipeBaseCount = 0
            }

            // Two fingers held still + a third finger taps left/right of them.
            if n == 2 {
                let ids = Set(touching.map { $0.identifier })
                if let tid = thirdID {
                    if ids == holdIDs && !ids.contains(tid) && ts - thirdStart <= tipTapMaxDuration {
                        fired.append(thirdIsLeft ? .twoHoldTapLeft : .twoHoldTapRight)
                        consumed = true   // never also report tap3 / swipe for this session
                    }
                    thirdID = nil
                    // keep holding: re-anchor so a further tap needs another short rest
                    holdSince = ts
                    holdAnchor = Dictionary(uniqueKeysWithValues: touching.map { ($0.identifier, $0.normalized.position) })
                    holdIDs = ids
                } else if ids != holdIDs {
                    holdIDs = ids
                    holdSince = ts
                    holdAnchor = Dictionary(uniqueKeysWithValues: touching.map { ($0.identifier, $0.normalized.position) })
                } else {
                    for f in touching {
                        if let a = holdAnchor[f.identifier],
                           hypotf(f.normalized.position.x - a.x, f.normalized.position.y - a.y) > holdStillMax {
                            holdSince = ts
                            holdAnchor = Dictionary(uniqueKeysWithValues: touching.map { ($0.identifier, $0.normalized.position) })
                            break
                        }
                    }
                }
            } else if n == 3 {
                if thirdID == nil, holdIDs.count == 2, ts - holdSince >= tipTapRestMin {
                    let held = touching.filter { holdIDs.contains($0.identifier) }
                    if held.count == 2, let o = touching.first(where: { !holdIDs.contains($0.identifier) }) {
                        let meanX = (held[0].normalized.position.x + held[1].normalized.position.x) / 2
                        thirdID = o.identifier
                        thirdStart = ts
                        thirdIsLeft = o.normalized.position.x < meanX
                        // a deliberate hold-tap is not a 3-finger tap
                        consumed = true
                    }
                }
                if thirdID == nil && holdIDs.count == 2 && ts - holdSince < tipTapRestMin {
                    // fingers landed together: ordinary 3-finger gesture, forget the hold
                    holdIDs = []
                }
            } else {
                holdIDs = []; holdAnchor = [:]; thirdID = nil
            }

            // Tip-tap: one finger resting, a second finger taps briefly beside it.
            if n == 1 {
                let f = touching[0]
                if let tid = tipID, restingID == f.identifier, tid != f.identifier {
                    if ts - tipStart <= tipTapMaxDuration {
                        fired.append(tipIsLeft ? .tipTapLeft : .tipTapRight)
                    }
                    tipID = nil
                }
                if restingID != f.identifier { restingID = f.identifier; restingSince = ts; tipID = nil }
            } else if n == 2 {
                if tipID == nil, let rid = restingID, ts - restingSince >= tipTapRestMin,
                   let r = touching.first(where: { $0.identifier == rid }),
                   let o = touching.first(where: { $0.identifier != rid }) {
                    tipID = o.identifier
                    tipStart = ts
                    tipIsLeft = o.normalized.position.x < r.normalized.position.x
                }
            } else {
                tipID = nil
                restingID = nil
            }
        }
        lock.unlock()
        if let cb = onGesture { fired.forEach { cb($0) } }
    }

    private func centroid(_ fs: [MTFinger]) -> MTPoint {
        var x: Float = 0, y: Float = 0
        for f in fs { x += f.normalized.position.x; y += f.normalized.position.y }
        let c = Float(max(fs.count, 1))
        return MTPoint(x: x / c, y: y / c)
    }
}
