//
//  CommandPaletteView.swift
//  Haze — views
//

import SwiftUI

struct CommandPaletteView: View {
    let ctx: AppActionContext
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var results: [AppAction] { CommandRegistry.search(query, in: ctx) }

    private func isEnabled(_ action: AppAction) -> Bool { action.isEnabled(ctx) }

    private func enabledIndex(from: Int, dir: Int) -> Int? {
        var i = from
        while results.indices.contains(i) {
            if isEnabled(results[i]) { return i }
            i += dir
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit(runSelected)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { isPresented = false; return .handled }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !results.isEmpty {
                separator
                resultList
            } else {
                separator
                Text("No matching commands")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
        .shadow(radius: 30, y: 12)
        .onAppear {
            selection = enabledIndex(from: 0, dir: 1) ?? 0
            DispatchQueue.main.async { fieldFocused = true }
        }
        .onChange(of: query) { _, _ in selection = enabledIndex(from: 0, dir: 1) ?? 0 }
    }

    private var separator: some View {
        Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, action in
                        row(action, selected: index == selection)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard isEnabled(action) else { return }
                                selection = index; runSelected()
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 360)
            .onChange(of: selection) { _, s in
                guard results.indices.contains(s) else { return }
                withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(results[s].id) }
            }
        }
    }

    private func row(_ action: AppAction, selected: Bool) -> some View {
        let on = isEnabled(action)
        return HStack(spacing: 10) {
            Text(action.title).lineLimit(1)
            Spacer(minLength: 12)
            Text(action.category.title).font(.caption).foregroundStyle(.secondary)
            if let sc = ctx.keyBindings.effective(for: action) {
                Text(sc.display)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .foregroundStyle(on ? Color.primary : Color.primary.opacity(0.4))
        .background(selected && on ? Color.accentColor.opacity(0.25) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        if let next = enabledIndex(from: selection + delta, dir: delta > 0 ? 1 : -1) {
            selection = next
        }
    }

    private func runSelected() {
        guard results.indices.contains(selection) else { return }
        let action = results[selection]
        guard isEnabled(action) else { return }
        isPresented = false
        action.run(ctx)
    }
}
