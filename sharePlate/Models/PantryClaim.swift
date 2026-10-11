// pantry claim

import Foundation
import SwiftData

@Model
final class PantryClaim {
    @Attribute(.unique) var gcfdLocationID: Int
    var pantryName: String
    var claimedByUserID: String
    var claimedAt: Date
    var isTemporarilyClosed: Bool
    var closedNote: String?

    init(
        gcfdLocationID: Int,
        pantryName: String,
        claimedByUserID: String,
        claimedAt: Date = Date(),
        isTemporarilyClosed: Bool = false,
        closedNote: String? = nil
    ) {
        self.gcfdLocationID = gcfdLocationID
        self.pantryName = pantryName
        self.claimedByUserID = claimedByUserID
        self.claimedAt = claimedAt
        self.isTemporarilyClosed = isTemporarilyClosed
        self.closedNote = closedNote
    }
}
