import AppKit
import SwiftUI
import Combine
import ServiceManagement
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    let store = ConfigStore()
    let recognizer = GestureRecognizer()
    let recorder = Recorder()
    private var statusItem: NSStatusItem?
    private var enableItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var retryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        setupMenu()

        let fire: @Sendable (Gesture) -> Void = { g in
            Task { @MainActor in AppDelegate.shared?.handle(g) }
        }
        recognizer.onGesture = fire
        let r = recognizer
        MultitouchManager.shared.onFrame = { fingers, ts in r.process(fingers, timestamp: ts) }
        ClickInterceptor.shared.recognizer = recognizer
        ClickInterceptor.shared.onGesture = fire

        store.$config
            .sink { [weak self] c in self?.apply(c) }
            .store(in: &cancellables)

        if !MultitouchManager.shared.start() {
            let a = NSAlert()
            a.messageText = "未找到触控板"
            a.informativeText = "无法加载 MultitouchSupport 或没有检测到触控板设备。可在菜单中选择“重新连接触控板”。"
            a.runModal()
        }
        ensureAccessibility()
        openSettings()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: gestures

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func handle(_ g: Gesture) {
        if recorder.isRecordingGesture {
            recorder.didDetect(g)
            return
        }
        guard store.config.enabled else { return }
        ActionRunner.run(store.action(for: g))
    }

    private func apply(_ c: AppConfig) {
        recognizer.swipeThreshold = Float(c.swipeThreshold)
        recognizer.tapMaxDuration = c.tapMaxDuration
        let mapped = Set([Gesture.click3, .click4].filter { (c.mappings[$0.rawValue]?.type ?? .none) != .none })
        ClickInterceptor.shared.update(enabled: c.enabled, mapped: mapped)
        enableItem?.state = c.enabled ? .on : .off
    }

    // MARK: permissions

    private func ensureAccessibility() {
        if AXIsProcessTrusted() {
            ClickInterceptor.shared.start()
            return
        }
        let a = NSAlert()
        a.messageText = "PadKit 需要“辅助功能”权限"
        a.informativeText = "发送快捷键、模拟中键、拦截多指点击和移动窗口都需要辅助功能权限。\n\n请在 系统设置 › 隐私与安全性 › 辅助功能 中打开 PadKit。授权后无需重启,PadKit 会自动生效。"
        a.addButton(withTitle: "打开系统设置")
        a.addButton(withTitle: "稍后")
        if a.runModal() == .alertFirstButtonReturn {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                guard AXIsProcessTrusted() else { return }
                if ClickInterceptor.shared.start() {
                    AppDelegate.shared?.retryTimer?.invalidate()
                    AppDelegate.shared?.retryTimer = nil
                }
            }
        }
    }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MultitouchManager.shared.restart()
        }
    }

    // MARK: menu

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "PadKit") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "PK"
        }
        let menu = NSMenu()
        let en = NSMenuItem(title: "启用手势", action: #selector(toggleEnabled), keyEquivalent: "")
        en.target = self
        en.state = store.config.enabled ? .on : .off
        menu.addItem(en)
        enableItem = en

        let li = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
        li.target = self
        li.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(li)
        loginItem = li

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let reconnect = NSMenuItem(title: "重新连接触控板", action: #selector(reconnect), keyEquivalent: "")
        reconnect.target = self
        menu.addItem(reconnect)
        let ax = NSMenuItem(title: "检查辅助功能权限", action: #selector(checkAX), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 PadKit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleEnabled() {
        store.config.enabled.toggle()
        store.save()
    }

    @objc private func toggleLogin() {
        LoginItem.set(!LoginItem.isEnabled)
        loginItem?.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func reconnect() { MultitouchManager.shared.restart() }

    @objc func repairAccessibility() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.zilonghe.padkit"]
        try? p.run()
        p.waitUntilExit()
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkAX() {
        if AXIsProcessTrusted() {
            ClickInterceptor.shared.start()
            let a = NSAlert(); a.messageText = "已获得辅助功能权限 ✅"; a.runModal()
        } else {
            ensureAccessibility()
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store, recorder: recorder)))
            w.title = "PadKit 设置"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 760, height: 600))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("PadKit: login item error \(error)")
        }
    }
}
