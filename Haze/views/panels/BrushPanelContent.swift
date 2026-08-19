//
//  BrushPanelContent.swift
//  Haze — views/panels
//

import SwiftUI

struct BrushPanelContent: View {
    @ObservedObject var store: Store
    @ObservedObject var editorStore: EditorStore
    @EnvironmentObject private var presets: BrushPresetStore
    @EnvironmentObject private var tips: BrushTipStore
    @StateObject private var previews = BrushPreviewCache()

    init(store: Store) {
        self.store = store
        self.editorStore = store.editorStore
    }

    @State private var gridView = true
    @State private var renaming: BrushPreset.ID?
    @State private var renameText = ""
    @State private var showTipPicker = false
    @FocusState private var renameFocused: Bool

    @AppStorage("brush.shapeExpanded") private var shapeExpanded = true
    @AppStorage("brush.pressureExpanded") private var pressureExpanded = true

    private let iconSize: CGFloat = 36

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(rgba: store.foregroundColor) },
                set: { store.foregroundColor = $0.rgbaFloats })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            presetSection
            strokeStrip
            Divider()
            ColorPicker("Color", selection: colorBinding, supportsOpacity: true)
            LabeledSlider(title: "Size", value: $editorStore.state.brush.size, range: 1...300, format: "%.0f px")
            LabeledSlider(title: "Hardness", value: $editorStore.state.brush.hardness, range: 0...1)
            LabeledSlider(title: "Opacity", value: $editorStore.state.brush.opacity, range: 0...1)
            LabeledSlider(title: "Flow", value: $editorStore.state.brush.flow, range: 0...1)
            LabeledSlider(title: "Spacing", value: $editorStore.state.brush.spacing, range: 0.01...1)
            Divider()
            shapeSection
            Divider()
            pressureSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, _ expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary).frame(width: 10)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preset section

    @ViewBuilder
    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Presets").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $gridView) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
                Menu {
                    Button("Import Brushes…") { BrushIOCommand.importBrushes(into: presets, store: store) }
                    Button("Export Brushes…") { BrushIOCommand.exportBrushes(presets, store: store) }
                    Divider()
                    Button("Restore Default Brushes") { presets.restoreDefaults() }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }

            if presets.presets.isEmpty {
                Text("Save your current brush with the + button.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
            } else if gridView {
                presetGrid
            } else {
                presetList
            }

            HStack(spacing: 8) {
                Button { presets.saveNew(from: store.editor.brush) } label: {
                    Label("Save", systemImage: "plus").labelStyle(.titleAndIcon)
                }.help("Save the current brush as a new preset")
                Button(role: .destructive) {
                    if let id = presets.selectedID { presets.delete(id) }
                } label: { Label("Delete", systemImage: "trash").labelStyle(.titleAndIcon) }
                    .disabled(presets.selectedID == nil)
                Spacer()
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var presetGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: iconSize), spacing: 4)], spacing: 4) {
                ForEach(presets.presets) { preset in
                    VStack(spacing: 2) {
                        presetIcon(preset)
                        if renaming == preset.id { renameField(preset).frame(width: iconSize) }
                    }
                    .contextMenu { presetMenu(preset) }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 150)
    }

    private var presetList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(presets.presets) { preset in
                    HStack(spacing: 8) {
                        presetIcon(preset, dim: 28)
                        nameLabel(preset)
                        Spacer()
                        Text("\(Int(preset.settings.size)) px · \(hardnessWord(preset.settings.hardness))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { select(preset) }
                    .contextMenu { presetMenu(preset) }
                }
            }
        }
        .frame(maxHeight: 150)
    }

    private func presetIcon(_ preset: BrushPreset, dim: CGFloat? = nil) -> some View {
        let side = dim ?? iconSize
        let selected = presets.selectedID == preset.id
        let dirty = selected && presets.isDirty(against: store.editor.brush)
        return ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.white)
            if let img = previews.icon(for: preset.settings, render: store.render) {
                Image(decorative: img, scale: 1).resizable().scaledToFit()
            }
        }
        .frame(width: side, height: side)
        .overlay(
            RoundedRectangle(cornerRadius: 4).strokeBorder(
                selected ? Color.accentColor : Color.secondary.opacity(0.25),
                style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: dirty ? [3, 2] : []))
        )
        .contentShape(Rectangle())
        .onTapGesture { select(preset) }
        .help(preset.name)
    }

    @ViewBuilder
    private func nameLabel(_ preset: BrushPreset) -> some View {
        if renaming == preset.id {
            renameField(preset)
        } else {
            Text(preset.name).font(.caption2).lineLimit(1).truncationMode(.tail)
                .onTapGesture(count: 2) { beginRename(preset) }
        }
    }

    @ViewBuilder
    private func renameField(_ preset: BrushPreset) -> some View {
        TextField("", text: $renameText)
            .textFieldStyle(.plain).font(.caption2).multilineTextAlignment(.center)
            .focused($renameFocused)
            .onSubmit { commitRename(preset.id) }
            .onExitCommand { renaming = nil }
            .onChange(of: renameFocused) { _, f in if !f && renaming == preset.id { commitRename(preset.id) } }
            .onAppear { renameFocused = true }
    }

    @ViewBuilder
    private func presetMenu(_ preset: BrushPreset) -> some View {
        Button("Rename") { beginRename(preset) }
        Button("Update from Current") { presets.updateFromCurrent(preset.id, with: store.editor.brush) }
        Button("Duplicate") { presets.duplicate(preset.id) }
        Divider()
        Button("Delete", role: .destructive) { presets.delete(preset.id) }
    }

    // MARK: - Shape section (tip texture + rotation + shape dynamics)

    @ViewBuilder
    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Shape", $shapeExpanded)
            if shapeExpanded {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 2) {
                        tipButton
                        Text(tipName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    VStack(spacing: 2) {
                        RotationDial(angleDegrees: $editorStore.state.brush.angle)
                            .frame(width: 44, height: 44)
                        Text("Rotation").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                LabeledSlider(title: "Angle", value: $editorStore.state.brush.angle, range: 0...360, format: "%.0f°")
                LabeledSlider(title: "Roundness", value: $editorStore.state.brush.roundness, range: 0.05...1)
                LabeledSlider(title: "Scatter", value: $editorStore.state.brush.scatter, range: 0...1)
                LabeledSlider(title: "Size Jitter", value: $editorStore.state.brush.sizeJitter, range: 0...1)
                LabeledSlider(title: "Angle Jitter", value: $editorStore.state.brush.angleJitter, range: 0...1)
                Toggle("Angle follows direction", isOn: $editorStore.state.brush.angleFollowsDirection)
                    .font(.caption).toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Pressure section (collapsible)

    @ViewBuilder
    private var pressureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Pressure", $pressureExpanded)
            if pressureExpanded {
                LabeledSlider(title: "→ Size", value: $editorStore.state.brush.pressureSize, range: 0...1)
                LabeledSlider(title: "→ Flow", value: $editorStore.state.brush.pressureFlow, range: 0...1)
                LabeledSlider(title: "→ Opacity", value: $editorStore.state.brush.pressureOpacity, range: 0...1)
            }
        }
    }

    private var tipName: String { tips.tip(store.editor.brush.tipID)?.name ?? "Round" }

    private var tipButton: some View {
        Button { showTipPicker = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.white)
                if let img = previews.tipIcon(for: store.editor.brush, render: store.render) {
                    Image(decorative: img, scale: 1).resizable().scaledToFit().padding(3)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .help("Brush tip shape")
        .popover(isPresented: $showTipPicker, arrowEdge: .bottom) { tipPicker }
    }

    private var tipPicker: some View {
        let tipIDs: [UUID?] = [nil] + tips.allTips.map { $0.id }
        return VStack(spacing: 6) {
            Text("Brush Tip").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 6)], spacing: 6) {
                    ForEach(Array(tipIDs.enumerated()), id: \.offset) { _, tipID in
                        tipCell(tipID)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 260, height: 220)
    }

    private func tipCell(_ tipID: UUID?) -> some View {
        let selected = store.editor.brush.tipID == tipID
        return VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.white)
                if let img = previews.tipThumb(for: tipID, render: store.render) {
                    Image(decorative: img, scale: 1).resizable().scaledToFit().padding(2)
                }
            }
            .frame(width: 48, height: 48)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(
                selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
            Text(tips.tip(tipID)?.name ?? "Round").font(.caption2).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.editor.brush.tipID = tipID
            showTipPicker = false
        }
        .help(tips.tip(tipID)?.name ?? "Round")
    }

    // MARK: - Live current-brush stroke strip

    private var strokeStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Current brush").font(.caption2).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.white)
                if let img = previews.strokeStrip(for: store.editor.brush, render: store.render) {
                    Image(decorative: img, scale: 1).resizable().scaledToFit()
                }
            }
            .frame(height: 46).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.25)))
        }
    }

    // MARK: - Actions

    private func select(_ preset: BrushPreset) {
        store.editor.brush = presets.settingsApplying(preset, keepingColorOf: store.editor.brush)
        presets.selectedID = preset.id
    }

    private func beginRename(_ preset: BrushPreset) {
        renameText = preset.name
        renaming = preset.id
    }

    private func commitRename(_ id: BrushPreset.ID) {
        presets.rename(id, renameText)
        renaming = nil
    }

    private func hardnessWord(_ h: Float) -> String { h >= 0.66 ? "hard" : (h <= 0.33 ? "soft" : "med") }
}
