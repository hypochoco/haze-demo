//
//  WelcomeView.swift
//  Haze — views/windows
//

import SwiftUI

struct WelcomeView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: AppUIState

    var body: some View {
        VStack(spacing: 20) {
            HazeMark(width: 72)
            VStack(spacing: 6) {
                Text("Welcome to Haze").font(.largeTitle.weight(.semibold))
                Text("Create a new canvas or open an existing file to begin.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    ui.showNewCanvas = true
                } label: {
                    Label("New Canvas", systemImage: "plus.square")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("n")

                Button {
                    DocumentIOCommand.open(store: store)
                } label: {
                    Label("Open…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("o")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(width: 320)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct HazeMark: View {
    var width: CGFloat = 72
    var color = Color(red: 166 / 255, green: 172 / 255, blue: 177 / 255)

    private let bandH = 64.0 / 520.0
    private let gapH  = 50.0 / 520.0

    var body: some View {
        VStack(spacing: width * gapH) {
            bar(412.0 / 520.0)
            bar(1.0)
            bar(344.0 / 520.0)
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }

    private func bar(_ frac: Double) -> some View {
        Capsule().fill(color).frame(width: width * frac, height: width * bandH)
    }
}
