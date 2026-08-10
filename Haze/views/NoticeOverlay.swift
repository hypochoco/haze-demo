//
//  NoticeOverlay.swift
//  Haze — views
//

import SwiftUI

struct NoticeOverlay: View {
    @ObservedObject var center: NoticeCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(center.notices) { notice in
                HStack(spacing: 8) {
                    Image(systemName: notice.severity.systemImage)
                    Text(notice.message)
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(notice.severity.tint.opacity(0.95), in: Capsule())
                .shadow(radius: 4, y: 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.2), value: center.notices)
    }
}

private extension NoticeSeverity {
    var tint: Color {
        switch self {
        case .info: return .gray
        case .warning: return .orange
        case .error: return .red
        }
    }
    var systemImage: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
