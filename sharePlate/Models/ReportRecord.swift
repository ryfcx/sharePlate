// report record

import Foundation
import SwiftData

@Model
final class ReportRecord {
    var listingID: String
    var reasonRaw: String
    var notes: String?
    var createdAt: Date
    var reportedByDeviceID: String

    init(
        listingID: String,
        reason: ReportReason,
        notes: String? = nil,
        createdAt: Date = Date(),
        reportedByDeviceID: String
    ) {
        self.listingID = listingID
        self.reasonRaw = reason.rawValue
        self.notes = notes
        self.createdAt = createdAt
        self.reportedByDeviceID = reportedByDeviceID
    }

    var reason: ReportReason {
        get { ReportReason(rawValue: reasonRaw) ?? .spam }
        set { reasonRaw = newValue.rawValue }
    }
}
