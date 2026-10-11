// gcfd database

import Foundation
import SQLite3
import UIKit

enum GCFDDatabase {
    // spot ready to become a food card
    struct Location {
        // stable id that lives through data refreshes
        let locationID: Int
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let phone: String?
        let summary: String
        let type: ResourceType
        let hours: String
        let serviceHours: [ServiceHours]
        let intervals: [OpeningInterval]
    }

    private static let resourceName = "gcfd_food"
    private static let resourceExtension = "db"

    // uses the downloaded copy if there is one, else the built in one
    static var activeDatabaseURL: URL? {
        let fileManager = FileManager.default
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let downloaded = support.appending(path: "\(resourceName).\(resourceExtension)")
            if fileManager.fileExists(atPath: downloaded.path) {
                return downloaded
            }
        }
        return Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
    }

    // loads every live spot with a map pin
    static func loadLocations() -> [Location] {
        guard let url = activeDatabaseURL else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let serviceHoursByLocation = loadServiceHours(db: db)
        return loadLocations(db: db, serviceHoursByLocation: serviceHoursByLocation)
    }

    // fingerprint to tell when we need to reimport
    static func datasetVersion() -> String? {
        guard let url = activeDatabaseURL else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT COUNT(*), COALESCE(MAX(last_updated), '') FROM locations WHERE is_active = 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let count = Int(sqlite3_column_int64(statement, 0))
        let maxUpdated = text(statement, 1)
        return "\(count):\(maxUpdated)"
    }

// service hours

    private struct ServiceAccumulator {
        var intervals: [OpeningInterval] = []
        var callForHours = false
        var notes: Set<String> = []
    }

    private static func loadServiceHours(db: OpaquePointer) -> [Int: [ServiceHours]] {
        let sql = """
        SELECT s.location_id, s.service_name,
               ss.day_of_week, ss.start_time, ss.end_time,
               ss.weeks_of_month, ss.days_of_month, ss.every_other_week,
               ss.contact_for_hours, ss.notes
        FROM services s
        LEFT JOIN service_schedules ss ON ss.location_service_id = s.location_service_id
        WHERE s.active = 1
        ORDER BY s.location_id, s.location_service_id, ss.day_of_week, ss.start_time;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }

        var rowsByLocation: [Int: [String: ServiceAccumulator]] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            let locationID = Int(sqlite3_column_int64(statement, 0))
            let serviceName = text(statement, 1)
            guard !serviceName.isEmpty else { continue }

            let dayOfWeek = Int(sqlite3_column_int64(statement, 2))
            let startMinutes = minutes(fromISO: text(statement, 3))
            let endMinutes = minutes(fromISO: text(statement, 4))
            let weeksText = text(statement, 5)
            let daysText = text(statement, 6)
            let everyOtherWeek = sqlite3_column_int64(statement, 7) == 1
            let contactForHours = text(statement, 8) == "1"
            let notes = text(statement, 9)

            var weeks = OpeningInterval.parseWeekOrdinals(weeksText)
            if weeks.isEmpty {
                weeks = OpeningInterval.parseWeekOrdinals(daysText)
            }

            var accumulators = rowsByLocation[locationID, default: [:]]
            var acc = accumulators[serviceName] ?? ServiceAccumulator()

            if contactForHours {
                acc.callForHours = true
            }
            if !notes.isEmpty {
                acc.notes.insert(notes)
            }

            if (1...7).contains(dayOfWeek),
               let startMinutes, let endMinutes, endMinutes > startMinutes {
                acc.intervals.append(
                    OpeningInterval(
                        weekday: dayOfWeek,
                        startMinutes: startMinutes,
                        endMinutes: endMinutes,
                        weeksOfMonth: weeks,
                        everyOtherWeek: everyOtherWeek,
                        notes: notes.isEmpty ? nil : notes
                    )
                )
            }

            accumulators[serviceName] = acc
            rowsByLocation[locationID] = accumulators
        }

        var result: [Int: [ServiceHours]] = [:]
        for (locationID, accumulators) in rowsByLocation {
            result[locationID] = accumulators.map { name, acc in
                ServiceHours(
                    serviceName: name,
                    intervals: acc.intervals,
                    callForHours: acc.callForHours,
                    notes: Array(acc.notes).sorted()
                )
            }.sorted { $0.serviceName < $1.serviceName }
        }

        return result
    }

// spots

    private static func loadLocations(db: OpaquePointer, serviceHoursByLocation: [Int: [ServiceHours]]) -> [Location] {
        let sql = """
        SELECT location_id, name, address1, address2, city, state, zip_code, \
        phone, latitude, longitude, food_programs, about_us
        FROM locations
        WHERE is_active = 1 AND latitude IS NOT NULL AND longitude IS NOT NULL;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var locations: [Location] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let locationID = Int(sqlite3_column_int64(statement, 0))
            let name = text(statement, 1)
            guard !name.isEmpty else { continue }

            let latitude = sqlite3_column_double(statement, 8)
            let longitude = sqlite3_column_double(statement, 9)
            guard latitude != 0 || longitude != 0 else { continue }

            let address = composeAddress(
                address1: text(statement, 2),
                address2: text(statement, 3),
                city: text(statement, 4),
                state: text(statement, 5),
                zip: text(statement, 6)
            )
            let phone = text(statement, 7)
            let programs = text(statement, 10)
            let about = text(statement, 11)

            let serviceHours = serviceHoursByLocation[locationID] ?? []
            let intervals = serviceHours.flatMap(\.intervals)
            let hours = hoursText(from: serviceHours, programs: programs)
            let summary = summaryText(about: about, programs: programs)

            locations.append(
                Location(
                    locationID: locationID,
                    name: name,
                    address: address,
                    latitude: latitude,
                    longitude: longitude,
                    phone: phone.isEmpty ? nil : phone,
                    summary: summary,
                    type: resourceType(programs: programs),
                    hours: hours,
                    serviceHours: serviceHours,
                    intervals: intervals
                )
            )
        }
        return locations
    }

// little mapping helpers

    private static func resourceType(programs: String) -> ResourceType {
        let p = programs.lowercased()
        if p.contains("mobile") { return .mobileDistribution }
        if p.contains("fridge") { return .communityFridge }
        if p.contains("meal") || p.contains("soup") || p.contains("kitchen") || p.contains("hot food") {
            return .mealProgram
        }
        return .pantry
    }

    private static func composeAddress(address1: String, address2: String, city: String, state: String, zip: String) -> String {
        var street = address1
        if !address2.isEmpty { street += " \(address2)" }

        var cityLine = city
        if !state.isEmpty { cityLine += cityLine.isEmpty ? state : ", \(state)" }
        if !zip.isEmpty { cityLine += " \(zip)" }

        return [street, cityLine]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func hoursText(from serviceHours: [ServiceHours], programs: String) -> String {
        guard !serviceHours.isEmpty else {
            return programs.isEmpty ? String(localized: "Call for hours") : programs
        }

        var sections: [String] = []
        for service in serviceHours {
            let lines = service.displayLines()
            if lines.isEmpty {
                if service.callForHours {
                    sections.append(String(localized: "\(service.serviceName): Call for hours"))
                }
                continue
            }
            if serviceHours.count == 1 {
                sections.append(lines.joined(separator: ", "))
            } else {
                sections.append("\(service.serviceName): \(lines.joined(separator: "; "))")
            }
        }

        let joined = sections.joined(separator: " · ")
        return joined.isEmpty ? (programs.isEmpty ? String(localized: "Call for hours") : programs) : joined
    }

    private static func summaryText(about: String, programs: String) -> String {
        let trimmed = plainText(fromHTML: about)
        if !trimmed.isEmpty {
            return String(trimmed.prefix(240))
        }
        if !programs.isEmpty {
            return programs
        }
        return String(localized: "Food assistance location.")
    }

    // cleans up messy about text with html in it
    private static func plainText(fromHTML html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let decoded: String
        if let data = trimmed.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ) {
            decoded = attributed.string
        } else {
            decoded = trimmed.replacingOccurrences(
                of: "<[^>]+>",
                with: " ",
                options: .regularExpression
            )
        }

        return decoded
            .components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // turns a time stamp into minutes past midnight
    private static func minutes(fromISO iso: String) -> Int? {
        guard let tRange = iso.range(of: "T") else { return nil }
        let time = iso[tRange.upperBound...]
        let parts = time.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: cString)
    }
}
