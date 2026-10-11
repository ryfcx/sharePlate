// opening interval

import Foundation

struct OpeningInterval: Codable, Hashable {
    // sunday is 1, monday is 2, and so on
    var weekday: Int
    // minutes after midnight when it opens
    var startMinutes: Int
    // minutes after midnight when it closes
    var endMinutes: Int
    // which weeks it runs, empty means every week
    var weeksOfMonth: [Int] = []
    // every other week spots are skipped for now
    var everyOtherWeek: Bool = false
    // extra schedule notes like holidays
    var notes: String?

    // true if this time falls inside
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

    // turns 1st and 3rd into numbers
    static func parseWeekOrdinals(_ text: String) -> [Int] {
        let map: [String: Int] = ["1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5]
        return text
            .split(separator: ",")
            .compactMap { map[$0.trimmingCharacters(in: .whitespaces).lowercased()] }
    }
}

// hours for one program at a spot
struct ServiceHours: Codable, Hashable, Identifiable {
    var id: String { serviceName }

    var serviceName: String
    var intervals: [OpeningInterval]
    // true when it says to call for hours
    var callForHours: Bool
    // saved notes like holidays and closures
    var notes: [String]

    // friendly lines for the screen
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
