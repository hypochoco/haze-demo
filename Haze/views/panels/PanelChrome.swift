//
//  PanelChrome.swift
//  Haze — views/panels
//

import SwiftUI

struct PanelChrome<Content: View>: View {
    let title: String
    var dragHandle: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let dragHandle { dragHandle }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            content.padding(10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
