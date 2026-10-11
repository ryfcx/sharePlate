//
//  countdowntext.swift
//  shareplate
//

import SwiftUI

// shows time left until deadline, use not live in lists for speed
struct CountdownText: View {
    let deadline: Date
    var prefix: String = ""
    var suffix: String = String(localized: " left")
    var live: Bool = true

    var body: some View {
        if live {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                label(at: context.date)
            }
        } else {
            label(at: Date())
        }
    }

    @ViewBuilder
    private func label(at now: Date) -> some View {
        if deadline <= now {
            Label("Expired", systemImage: "clock.badge.xmark")
                .foregroundStyle(Theme.Palette.urgentRed)
        } else {
            Label {
                Text("\(prefix)\(Self.relative(from: now, to: deadline))\(suffix)")
            } icon: {
                Image(systemName: "clock")
            }
            .foregroundStyle(timeColor(now: now))
        }
    }

    private func timeColor(now: Date) -> Color {
        let interval = deadline.timeIntervalSince(now)
        if interval <= MapBrowseLogic.closingSoonThreshold {
            return Theme.Palette.accentOrange
        }
        return Theme.Palette.mutedText
    }

    static func relative(from: Date, to: Date) -> String {
        let seconds = Int(to.timeIntervalSince(from))
        guard seconds > 0 else { return String(localized: "0m") }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return String(localized: "\(days)d \(hours)h") }
        if hours > 0 { return String(localized: "\(hours)h \(minutes)m") }
        return String(localized: "\(minutes)m")
    }
}
