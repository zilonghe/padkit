import SwiftUI
import AppKit

@MainActor
struct SettingsView: View {
    @ObservedObject var store: ConfigStore
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

    private func row(_ g: Gesture) -> some View {
        let b = binding(g)
        return HStack {
            Text(g.title).frame(width: 220, alignment: .leading)
            Picker("", selection: b.type) {
                ForEach(ActionType.allCases) { t in Text(t.title).tag(t) }
            }
            .labelsHidden()
            .frame(width: 150)
            TextField(b.wrappedValue.type.placeholder, text: b.value)
                .textFieldStyle(.roundedBorder)
                .disabled(!b.wrappedValue.type.needsValue)
        }
    }

    private func binding(_ g: Gesture) -> Binding<ActionConfig> {
        Binding(
            get: { store.action(for: g) },
            set: { store.config.mappings[g.rawValue] = $0; savedNote = "" }
        )
    }
}
