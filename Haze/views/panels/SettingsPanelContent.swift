//
//  SettingsPanelContent.swift
//  Haze — views/panels
//

import SwiftUI

struct SettingsPanelContent: View {
    @ObservedObject var store: Store
    @ObservedObject var config: Config
    @ObservedObject var keyBindings: KeyBindingStore

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            ShortcutsEditor(keyBindings: keyBindings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 460, height: 460)
    }

    // MARK: General (existing catalog)

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(SettingsCatalog.grouped, id: \.category.id) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.category.rawValue.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.items) { item in row(item) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func row(_ item: SettingDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            control(item)
            if !item.help.isEmpty {
                Text(item.help)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.requiresRelaunch {
                Label("Applies to canvases opened afterward", systemImage: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func control(_ item: SettingDescriptor) -> some View {
        switch item.control {
        case let .toggle(get, set):
            Toggle(item.title, isOn: binding(get: { get(config) }, set: { set(config, $0) }))

        case let .intStepper(range, step, get, set):
            Stepper(value: binding(get: { get(config) }, set: { set(config, $0) }), in: range, step: step) {
                HStack {
                    Text(item.title)
                    Spacer()
                    Text("\(get(config))").foregroundStyle(.secondary).monospacedDigit()
                }
            }

        case let .doubleSlider(range, step, get, set):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title)
                    Spacer()
                    Text(String(format: "%.2f", get(config))).foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: binding(get: { get(config) }, set: { set(config, $0) }), in: range, step: step)
            }
        }
    }

    private func binding<V>(get: @escaping () -> V, set: @escaping (V) -> Void) -> Binding<V> {
        Binding(get: get, set: { set($0); store.configDidChange() })
    }
}

struct ShortcutsEditor: View {
    @ObservedObject var keyBindings: KeyBindingStore
    @State private var note: String?

    private var grouped: [(category: ActionCategory, items: [AppAction])] {
        let bindable = CommandRegistry.all.filter { $0.shortcut != nil }
        return Dictionary(grouping: bindable, by: \.category)
            .map { (category: $0.key, items: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.category.order < $1.category.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(grouped, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.category.title.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.items) { action in shortcutRow(action) }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if let note {
                    Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Reset All") { keyBindings.resetAll(); note = "Restored default shortcuts" }
                    .controlSize(.small)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func shortcutRow(_ action: AppAction) -> some View {
        HStack(spacing: 8) {
            Text(action.title).lineLimit(1)
            Spacer(minLength: 8)
            if keyBindings.isCustomized(action.id) {
                Button {
                    keyBindings.reset(action.id)
                    note = "Reset \(action.title)"
                } label: {
                    Image(systemName: "arrow.uturn.backward").font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Reset to default")
            }
            ShortcutRecorderField(shortcut: keyBindings.effective(for: action)) { captured in
                capture(captured, for: action)
            }
            .frame(width: 116, height: 22)
        }
    }

    private func capture(_ shortcut: ActionShortcut?, for action: AppAction) {
        guard let shortcut else {
            keyBindings.setShortcut(nil, for: action.id)
            note = "Cleared \(action.title)"
            return
        }
        if let other = keyBindings.conflict(for: shortcut, excluding: action.id) {
            keyBindings.setShortcut(nil, for: other.id)
            keyBindings.setShortcut(shortcut, for: action.id)
            note = "\(shortcut.display) reassigned from \(other.title)"
        } else {
            keyBindings.setShortcut(shortcut, for: action.id)
            note = nil
        }
    }
}
