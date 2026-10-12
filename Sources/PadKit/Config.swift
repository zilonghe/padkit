import Foundation
import Combine

enum ActionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, shortcut, middleClick, launchApp, shell, snapLeft, snapRight, maximize
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "无"
        case .shortcut: return "键盘快捷键"
        case .middleClick: return "鼠标中键"
        case .launchApp: return "打开应用"
        case .shell: return "Shell 命令"
        case .snapLeft: return "窗口左半屏"
        case .snapRight: return "窗口右半屏"
        case .maximize: return "窗口最大化"
        }
    }
    var placeholder: String {
        switch self {
        case .shortcut: return "如 cmd+shift+]"
        case .launchApp: return "应用名 / bundle id / 路径"
        case .shell: return "如 open ~/Downloads"
        default: return ""
        }
    }
    var needsValue: Bool { self == .shortcut || self == .launchApp || self == .shell }
}

struct ActionConfig: Codable, Equatable, Sendable {
    var type: ActionType
    var value: String

    init(_ type: ActionType, _ value: String = "") { self.type = type; self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(ActionType.self, forKey: .type)) ?? .none
        value = (try? c.decodeIfPresent(String.self, forKey: .value)) ?? ""
    }
}

struct AppConfig: Codable, Equatable {
    var enabled: Bool = true
    var swipeThreshold: Double = 0.12
    var tapMaxDuration: Double = 0.30
    var mappings: [String: ActionConfig] = AppConfig.defaultMappings

    static let defaultMappings: [String: ActionConfig] = [
        Gesture.tap3.rawValue: ActionConfig(.middleClick),
        Gesture.tap4.rawValue: ActionConfig(.shortcut, "ctrl+up"),
        Gesture.tap5.rawValue: ActionConfig(.shell, "open ~/Downloads"),
        Gesture.click3.rawValue: ActionConfig(.none),
        Gesture.click4.rawValue: ActionConfig(.none),
        Gesture.swipe3Up.rawValue: ActionConfig(.maximize),
        Gesture.swipe3Down.rawValue: ActionConfig(.none),
        Gesture.swipe3Left.rawValue: ActionConfig(.snapLeft),
        Gesture.swipe3Right.rawValue: ActionConfig(.snapRight),
        Gesture.swipe4Up.rawValue: ActionConfig(.none),
        Gesture.swipe4Down.rawValue: ActionConfig(.none),
        Gesture.swipe4Left.rawValue: ActionConfig(.none),
        Gesture.swipe4Right.rawValue: ActionConfig(.none),
        Gesture.tipTapLeft.rawValue: ActionConfig(.shortcut, "cmd+shift+["),
        Gesture.tipTapRight.rawValue: ActionConfig(.shortcut, "cmd+shift+]"),
    ]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        swipeThreshold = (try? c.decodeIfPresent(Double.self, forKey: .swipeThreshold)) ?? 0.12
        tapMaxDuration = (try? c.decodeIfPresent(Double.self, forKey: .tapMaxDuration)) ?? 0.30
        let m = (try? c.decodeIfPresent([String: ActionConfig].self, forKey: .mappings)) ?? [:]
        mappings = AppConfig.defaultMappings.merging(m) { _, new in new }
    }
}

@MainActor
final class ConfigStore: ObservableObject {
    @Published var config = AppConfig()

    let directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PadKit", isDirectory: true)
    var fileURL: URL { directory.appendingPathComponent("config.json") }

    init() { load() }

    func load() {
        if let data = try? Data(contentsOf: fileURL) {
            do { config = try JSONDecoder().decode(AppConfig.self, from: data) }
            catch { NSLog("PadKit: config parse error \(error); using defaults") ; config = AppConfig() }
        } else {
            config = AppConfig()
            save()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(config).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("PadKit: save failed \(error)")
        }
    }

    func action(for g: Gesture) -> ActionConfig { config.mappings[g.rawValue] ?? ActionConfig(.none) }
}
