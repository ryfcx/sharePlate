import Foundation

enum ContentSubmissionError: LocalizedError {
    case contentTooLarge
    case sessionChanged
    case rateLimited
    case photoRequired

    var errorDescription: String? {
        switch self {
        case .contentTooLarge:
            String(localized: "Use a title under 120 characters, notes under 1,000 characters, and a photo under 5 MB.")
        case .sessionChanged:
            String(localized: "Your session changed. Please open the app again.")
        case .rateLimited:
            String(localized: "You have posted several listings recently. Please try again later.")
        case .photoRequired:
            String(localized: "Please choose your photo again and retry.")
        }
    }
}
