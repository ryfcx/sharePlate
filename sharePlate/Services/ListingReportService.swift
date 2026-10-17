import Foundation
import Supabase

enum ReportSubmissionError: LocalizedError {
    case listingUnavailable
    case ownListing
    case notesTooLong
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .listingUnavailable:
            return String(localized: "This listing is not available to report. Refresh and try again.")
        case .ownListing:
            return String(localized: "You can't report your own listing.")
        case .notesTooLong:
            return String(localized: "Keep your report notes under 1,000 characters.")
        case .rateLimited:
            return String(localized: "You've sent several reports recently. Please try again in an hour.")
        }
    }
}

enum ListingReportService {
    static func submit(listingID: UUID, reason: ReportReason, notes: String?) async throws {
        struct Input: Encodable {
            let p_listing_id: UUID
            let p_reason: String
            let p_notes: String?
        }
        do {
            let _: UUID = try await SupabaseManager.client
                .rpc("submit_listing_report", params: Input(
                    p_listing_id: listingID, p_reason: reason.rawValue, p_notes: notes))
                .execute().value
        } catch let error as PostgrestError {
            switch error.message {
            case "report_listing_unavailable": throw ReportSubmissionError.listingUnavailable
            case "report_own_listing": throw ReportSubmissionError.ownListing
            case "report_notes_too_long": throw ReportSubmissionError.notesTooLong
            case "report_rate_limited": throw ReportSubmissionError.rateLimited
            default: throw error
            }
        }
    }
}
