import SwiftUI
import AppKit

@MainActor
struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var recorder: Recorder
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var savedNote = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                Toggle("启用手势", isOn: $store.config.enabled)
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { v in
                        LoginItem.set(v)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Spacer()
            }
            HStack {
                Text("滑动阈值")
                Slider(value: $store.config.swipeThreshold, in: 0.05...0.4)
                Text(String(format: "%.2f", store.config.swipeThreshold)).monospacedDigit().frame(width: 40)
                Text("轻点最长时长")
                Slider(value: $store.config.tapMaxDuration, in: 0.1...0.6)
                Text(String(format: "%.2fs", store.config.tapMaxDuration)).monospacedDigit().frame(width: 50)
            }
            Divider()
            recordPanel
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Gesture.allCases) { g in
                        row(g)
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            HStack {
                Text(store.fileURL.path).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(savedNote).font(.caption).foregroundColor(.green)
                Button("修复授权") { AppDelegate.shared?.repairAccessibility() }
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
                Button("恢复默认") { store.config = AppConfig() }
                Button("重新载入") { store.load(); savedNote = "已载入" }
                Button("保存") { store.save(); savedNote = "已保存" }
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder
    private var recordPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if recorder.isRecordingGesture {
                    ProgressView().controlSize(.small)
                    Text("请在触控板上做一个手势…(剩余 \(recorder.secondsLeft) 秒)")
                    Button("取消") { recorder.stopGesture() }
                } else {
                    Button("录制手势") { recorder.startGesture() }
                    if recorder.gestureTimedOut {
                        Text("超时,未识别到手势").foregroundColor(.orange)
                    } else if recorder.lastGesture == nil {
                        Text("点击后在触控板上做手势,将自动识别并在下方编辑它的动作。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            if let g = recorder.lastGesture, !recorder.isRecordingGesture {
                HStack(spacing: 12) {
                    Text("识别到:").foregroundColor(.secondary)
                    Text(g.title).font(.headline)
                }
                editor(g)
                HStack {
                    Button("保存") { store.save(); savedNote = "已保存 \(g.title)" }
                    Button("再录一个") { recorder.startGesture() }
                    Button("关闭") { recorder.clearGesture() }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private func row(_ g: Gesture) -> some View {
        HStack {
            Text(g.title)
                .fontWeight(recorder.lastGesture == g ? .bold : .regular)
                .frame(width: 220, alignment: .leading)
            editor(g)
        }
    }

    private func editor(_ g: Gesture) -> some View {
        let b = binding(g)
        let isShortcut = b.wrappedValue.type == .shortcut
        let capturing = recorder.shortcutTarget == g
        return HStack {
            Picker("", selection: b.type) {
                ForEach(ActionType.allCases) { t in Text(t.title).tag(t) }
            }
            .labelsHidden()
            .frame(width: 150)
            TextField(b.wrappedValue.type.placeholder, text: b.value)
                .textFieldStyle(.roundedBorder)
                .disabled(!b.wrappedValue.type.needsValue || capturing)
            if isShortcut {
                if capturing {
                    Button("按下组合键…(\(recorder.secondsLeft)s) 取消") { recorder.cancelShortcut() }
                } else {
                    Button("录制快捷键") {
                        recorder.startShortcut(for: g) { s in
                            store.config.mappings[g.rawValue] = ActionConfig(.shortcut, s)
                            savedNote = "未保存"
                        }
                    }
                }
            }
        }
    }

    private func binding(_ g: Gesture) -> Binding<ActionConfig> {
        Binding(
            get: { store.action(for: g) },
            set: { store.config.mappings[g.rawValue] = $0; savedNote = "" }
        )
    }
}
