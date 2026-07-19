//
//  LocationDetail.swift
//  sharePlate
//

import SwiftData

/// Lightweight navigation token — avoids eager NavigationLink destination builds.
enum LocationDetail: Hashable {
    case listing(PersistentIdentifier)
    case resource(PersistentIdentifier)
}
