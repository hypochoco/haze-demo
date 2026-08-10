//
//  NoticeCenter.swift
//  Haze — notifications
//

import Foundation
import Combine

@MainActor
final class NoticeCenter: ObservableObject {
    @Published private(set) var notices: [Notice] = []
    private let maxVisible = 4

    func post(_ message: String, _ severity: NoticeSeverity = .info, duration: TimeInterval = 3) {
        notices.removeAll { $0.message == message }
        let notice = Notice(message: message, severity: severity)
        notices.append(notice)
        if notices.count > maxVisible { notices.removeFirst(notices.count - maxVisible) }

        let id = notice.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            self?.dismiss(id)
        }
    }

    func dismiss(_ id: UUID) { notices.removeAll { $0.id == id } }
}
