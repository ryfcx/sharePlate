//
//  OpeningInterval.swift
//  sharePlate
//
//  One weekly opening window for a food resource, used to compute "open now".
//

import Foundation

struct OpeningInterval: Codable, Hashable {
    /// 1 = Sunday, 2 = Monday, … 7 = Saturday (matches `Calendar.component(.weekday:)`).
    var weekday: Int
    /// Minutes since midnight when the window opens.
    var startMinutes: Int
    /// Minutes since midnight when the window closes.
    var endMinutes: Int
    /// Which weeks of the month this window applies to (1 = first, … 5 = fifth).
    /// Empty means every week.
    var weeksOfMonth: [Int] = []
    /// Bi-weekly schedules cannot be resolved without an anchor date from the API,
    /// so these intervals are excluded from automatic "open now" checks.
    var everyOtherWeek: Bool = false
    /// Free-text schedule notes (holidays, closures, location-specific rules).
    var notes: String?

    /// Whether `date` falls inside this window.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard !everyOtherWeek else { return false }

        let weekday = calendar.component(.weekday, from: date)
        guard weekday == self.weekday else { return false }

        if !weeksOfMonth.isEmpty {
            let week = calendar.component(.weekOfMonth, from: date)
            guard weeksOfMonth.contains(week) else { return false }
        }

        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return minutes >= startMinutes && minutes < endMinutes
    }

    /// Parses ordinals like `"1st, 3rd"` into `[1, 3]`.
    static func parseWeekOrdinals(_ text: String) -> [Int] {
        let map: [String: Int] = ["1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5]
        return text
            .split(separator: ",")
            .compactMap { map[$0.trimmingCharacters(in: .whitespaces).lowercased()] }
    }
}

/// Hours for one program/service offered at a location (e.g. pantry vs. hot meals).
struct ServiceHours: Codable, Hashable, Identifiable {
    var id: String { serviceName }

    var serviceName: String
    var intervals: [OpeningInterval]
    /// True when the schedule says to call for hours instead of listing times.
    var callForHours: Bool
    /// Aggregated notes from schedule rows (holidays, closures, special rules).
    var notes: [String]

    /// Human-readable lines for UI display.
    func displayLines(calendar: Calendar = .current) -> [String] {
        var lines: [String] = []

        if callForHours && intervals.isEmpty {
            lines.append(String(localized: "Call for hours"))
        }

        let weekdayNames = [
            "",
            String(localized: "Sun"),
            String(localized: "Mon"),
            String(localized: "Tue"),
            String(localized: "Wed"),
            String(localized: "Thu"),
            String(localized: "Fri"),
            String(localized: "Sat"),
        ]
        for interval in intervals {
            guard (1...7).contains(interval.weekday) else { continue }
            let day = weekdayNames[interval.weekday]
            let start = Self.formatMinutes(interval.startMinutes)
            let end = Self.formatMinutes(interval.endMinutes)
            var line = "\(day) \(start)–\(end)"

            if !interval.weeksOfMonth.isEmpty {
                let ordinals = interval.weeksOfMonth.map(Self.ordinal).joined(separator: ", ")
                line += " " + String(localized: "(\(ordinals) \(day) of month)")
            }
            if interval.everyOtherWeek {
                line += " " + String(localized: "(every other week)")
            }
            if let note = interval.notes, !note.isEmpty {
                line += " — \(note)"
            }
            lines.append(line)
        }

        for note in notes where !note.isEmpty && !lines.contains(where: { $0.contains(note) }) {
            lines.append(note)
        }

        return lines
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    nonisolated private static func ordinal(_ week: Int) -> String {
        switch week {
        case 1: return String(localized: "1st")
        case 2: return String(localized: "2nd")
        case 3: return String(localized: "3rd")
        case 4: return String(localized: "4th")
        case 5: return String(localized: "5th")
        default: return "\(week)"
        }
    }
}
