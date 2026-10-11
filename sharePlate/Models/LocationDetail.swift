// location detail

import SwiftData

// light token so screens open fast
enum LocationDetail: Hashable {
    case listing(PersistentIdentifier)
    case resource(PersistentIdentifier)
}
