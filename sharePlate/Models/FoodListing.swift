//
//  FoodListing.swift
//  sharePlate
//

import Foundation
import SwiftData
import CoreLocation
import SwiftUI

@Model
final class FoodListing {
    var title: String
    var details: String
    var quantity: String
    /// Defaults allow SwiftData lightweight migration from older schemas.
    var categoryRaw: String = FoodCategory.mixed.rawValue
    var quantitySizeRaw: String = QuantitySize.feeds3to5.rawValue
    var pickupTypeRaw: String = PickupType.meetOutside.rawValue
    /// Public, approximate neighborhood/city label (e.g. "Logan Square").
    var area: String = ""
    @Attribute(.externalStorage) var photo: Data?
    /// Public Supabase Storage URL for the listing photo, when synced.
    var photoURL: String?
    var pickupAddress: String
    var latitude: Double
    var longitude: Double
    var pickupDeadline: Date
    var pickupNotes: String?
    var contactInstructions: String?
    var statusRaw: String
    var createdAt: Date
    /// Supabase row id when synced to the cloud.
    var remoteID: String?
    var postedByDeviceID: String
    var claimedByDeviceID: String?
    /// While reserved, the hold expires at this time and the listing reopens.
    var reservedUntil: Date?
    /// Device IDs waiting for the food to reopen.
    var waitlistDeviceIDs: [String] = []
    /// How far the donor will travel for drop-off listings, in meters.
    var dropOffRadiusMeters: Double?
    /// Total packages listed (0 = legacy quantity-size mapping).
    var packageCount: Int = 0
    /// Max packages one person can reserve at once (0 = all remaining).
    var maxPackagesPerBooking: Int = 0
    /// Packages still available (0 = same as packageCount until first reserve).
    var packagesRemaining: Int = 0

    /// Initial hold while the picker confirms; extended to pickup deadline once reserved.
    static let reservationHold: TimeInterval = 30 * 60

    init(
        title: String,
        details: String,
        quantity: String,
        category: FoodCategory = .mixed,
        quantitySize: QuantitySize = .feeds3to5,
        pickupType: PickupType = .meetOutside,
        area: String = "",
        photo: Data? = nil,
        photoURL: String? = nil,
        pickupAddress: String,
        latitude: Double,
        longitude: Double,
        pickupDeadline: Date,
        pickupNotes: String? = nil,
        contactInstructions: String? = nil,
        status: ListingStatus = .available,
        createdAt: Date = Date(),
        remoteID: String? = nil,
        postedByDeviceID: String,
        claimedByDeviceID: String? = nil,
        reservedUntil: Date? = nil,
        waitlistDeviceIDs: [String] = [],
        dropOffRadiusMeters: Double? = nil,
        packageCount: Int = 0,
        maxPackagesPerBooking: Int = 0,
        packagesRemaining: Int = 0
    ) {
        self.title = title
        self.details = details
        self.quantity = quantity
        self.categoryRaw = category.rawValue
        self.quantitySizeRaw = quantitySize.rawValue
        self.pickupTypeRaw = pickupType.rawValue
        self.area = area
        self.photo = photo
        self.photoURL = photoURL
        self.pickupAddress = pickupAddress
        self.latitude = latitude
        self.longitude = longitude
        self.pickupDeadline = pickupDeadline
        self.pickupNotes = pickupNotes
        self.contactInstructions = contactInstructions
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
        self.remoteID = remoteID
        self.postedByDeviceID = postedByDeviceID
        self.claimedByDeviceID = claimedByDeviceID
        self.reservedUntil = reservedUntil
        self.waitlistDeviceIDs = waitlistDeviceIDs
        self.dropOffRadiusMeters = dropOffRadiusMeters ?? ListingDetailsCodec.decode(details).dropOffRadiusMeters
        self.packageCount = packageCount
        self.maxPackagesPerBooking = maxPackagesPerBooking
        self.packagesRemaining = packagesRemaining
        if packageCount == 0 {
            syncPackageFieldsFromDetails()
        }
    }

    // MARK: - Typed accessors

    var status: ListingStatus {
        get { ListingStatus.from(raw: statusRaw) }
        set { statusRaw = newValue.rawValue }
    }

    var category: FoodCategory {
        get { FoodCategory(rawValue: categoryRaw) ?? .mixed }
        set { categoryRaw = newValue.rawValue }
    }

    var quantitySize: QuantitySize {
        get { QuantitySize(rawValue: quantitySizeRaw) ?? .feeds3to5 }
        set { quantitySizeRaw = newValue.rawValue }
    }

    var pickupType: PickupType {
        get { PickupType(rawValue: pickupTypeRaw) ?? .meetOutside }
        set { pickupTypeRaw = newValue.rawValue }
    }

    var isDropOff: Bool { pickupType == .communityFridge }

    var dropOffRadiusLabel: String? {
        guard isDropOff, let meters = dropOffRadiusMeters else { return nil }
        return DropOffRadius.nearest(to: meters)?.displayName
    }

    func syncDropOffRadiusFromDetails() {
        syncPackageFieldsFromDetails()
    }

    func syncPackageFieldsFromDetails() {
        let payload = ListingDetailsCodec.decode(details)
        if let meters = payload.dropOffRadiusMeters {
            dropOffRadiusMeters = meters
        }
        if let total = payload.packageCount {
            packageCount = total
        }
        if let max = payload.maxPackagesPerBooking {
            maxPackagesPerBooking = max
        }
        if let remaining = payload.packagesRemaining {
            packagesRemaining = remaining
        }
    }

    func refreshDetailsField() {
        details = ListingDetailsCodec.encode(ListingDetailsCodec.Payload(
            dropOffRadiusMeters: dropOffRadiusMeters,
            packageCount: packageCount > 0 ? packageCount : nil,
            maxPackagesPerBooking: maxPackagesPerBooking > 0 ? maxPackagesPerBooking : nil,
            packagesRemaining: packageCount > 0 ? effectivePackagesRemaining : nil
        ))
    }

    var totalPackages: Int {
        packageCount > 0 ? packageCount : quantitySize.packageCount
    }

    var effectiveMaxPerBooking: Int {
        if maxPackagesPerBooking > 0 {
            return min(maxPackagesPerBooking, totalPackages)
        }
        return totalPackages
    }

    /// Packages left to reserve (before an active hold).
    var effectivePackagesRemaining: Int {
        if packageCount > 0 {
            if packagesRemaining > 0 { return packagesRemaining }
            return hasActiveHandoff ? 0 : packageCount
        }
        return hasActiveHandoff ? 0 : totalPackages
    }

    /// Packages in the current or most recent reservation.
    var activeReservedPackageCount: Int {
        if let count = coordination.reservedPackageCount, count > 0 { return count }
        if hasActiveHandoff { return min(effectiveMaxPerBooking, totalPackages) }
        return totalPackages
    }

    var packagesShortLabel: String {
        "\(activeReservedPackageCount)x"
    }

    var packagesLabel: String {
        let count = activeReservedPackageCount
        return count == 1 ? "1 pack" : "\(count) packs"
    }

    static func quantityLabel(packageCount: Int, maxPerBooking: Int) -> String {
        if maxPerBooking >= packageCount {
            return packageCount == 1 ? "1 package" : "\(packageCount) packages"
        }
        return "\(packageCount) packages · max \(maxPerBooking) each"
    }

    var packageSummaryLabel: String {
        if packageCount > 0 {
            return Self.quantityLabel(packageCount: totalPackages, maxPerBooking: effectiveMaxPerBooking)
        }
        return quantitySize.displayName
    }

    var needsPackageSelectionOnReserve: Bool {
        effectivePackagesRemaining > 1 || effectiveMaxPerBooking < totalPackages
    }

    var coordination: ReservationCoordination {
        get { ReservationCoordinationCodec.decode(from: contactInstructions) }
        set { contactInstructions = ReservationCoordinationCodec.encode(newValue) }
    }

    /// Pickup instructions for reserved handoffs — includes listings that set details at post time.
    var publishedPickupInstructions: ReservationCoordination {
        let decoded = coordination
        if decoded.isReadyForConsumer { return decoded }
        if decoded.providerSetupComplete {
            var patched = decoded
            patched.instructionsPublished = true
            return patched
        }
        return decoded
    }

    var hasPublishedPickupInstructions: Bool {
        publishedPickupInstructions.isReadyForConsumer
    }

    var reservationCode: String {
        bookingCode
    }

    /// Four-character booking id shown on the dashboard, e.g. `1234`.
    var bookingCode: String {
        if let remoteID {
            let digits = remoteID.filter(\.isNumber)
            if digits.count >= 4 {
                return String(digits.suffix(4))
            }
            let alnum = remoteID.filter { $0.isLetter || $0.isNumber }.uppercased()
            if alnum.count >= 4 {
                return String(alnum.suffix(4))
            }
        }
        return String(format: "%04d", abs(title.hashValue) % 10_000)
    }

    // MARK: - Location

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Coarsened coordinate (~1 km grid) used for public map display so the
    /// exact address is not revealed before someone reserves the pickup.
    var publicCoordinate: CLLocationCoordinate2D {
        func blur(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        return CLLocationCoordinate2D(latitude: blur(latitude), longitude: blur(longitude))
    }

    var areaLabel: String {
        area.isEmpty ? "Nearby" : area
    }

    // MARK: - Timing

    var isExpired: Bool {
        pickupDeadline < Date()
    }

    /// Available food whose deadline is within two hours is treated as urgent.
    var isUrgent: Bool {
        guard !isExpired else { return false }
        return pickupDeadline.timeIntervalSinceNow <= 2 * 60 * 60
    }

    var reservationActive: Bool {
        guard status == .reserved, let until = reservedUntil else { return false }
        return until > Date()
    }

    var reservationRemaining: TimeInterval? {
        guard let until = reservedUntil, until > Date() else { return nil }
        return until.timeIntervalSinceNow
    }

    var postedRelativeText: String {
        let seconds = Int(Date().timeIntervalSince(createdAt))
        if seconds < 60 { return "Posted just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "Posted \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "Posted \(hours)h ago" }
        return "Posted \(hours / 24)d ago"
    }

    var expiresText: String {
        "Expires \(pickupDeadline.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - Status

    /// Active reserved handoffs stay completable even after the listing deadline passes.
    var hasActiveHandoff: Bool {
        guard claimedByDeviceID != nil else { return false }
        return status == .reserved || status == .readyForPickup
    }

    /// Display status accounting for elapsed deadline and lapsed reservations.
    var effectiveStatus: ListingStatus {
        if status == .pickedUp { return .pickedUp }
        if hasActiveHandoff { return status }
        if isExpired { return .expired }
        if status == .reserved, let until = reservedUntil, until < Date() { return .available }
        return status
    }

    /// True when completing the current reservation should relist remaining packages.
    var shouldReopenAfterHandoffCompletion: Bool {
        hasActiveHandoff && packageCount > 0 && packagesRemaining > 0
    }

    /// Quick visual indicator color for cards and pins.
    var indicatorColor: Color {
        switch effectiveStatus {
        case .expired, .pickedUp:
            return Theme.Palette.mutedText
        case .reserved:
            return Theme.Palette.accentOrange
        case .readyForPickup:
            return Theme.Palette.mealBlue
        case .available:
            if isUrgent { return Theme.Palette.urgentRed }
            if totalPackages == 1 { return Theme.Palette.limitedYellow }
            return Theme.Palette.primaryGreen
        }
    }
}

enum ListingDetailsCodec {
    struct Payload {
        var dropOffRadiusMeters: Double?
        var packageCount: Int?
        var maxPackagesPerBooking: Int?
        var packagesRemaining: Int?
    }

    static func encode(_ payload: Payload) -> String {
        var parts: [String] = []
        if let meters = payload.dropOffRadiusMeters {
            parts.append("dropoff_radius_meters=\(Int(meters))")
        }
        if let total = payload.packageCount {
            parts.append("packages_total=\(total)")
        }
        if let max = payload.maxPackagesPerBooking {
            parts.append("packages_max=\(max)")
        }
        if let remaining = payload.packagesRemaining {
            parts.append("packages_remaining=\(remaining)")
        }
        return parts.joined(separator: ";")
    }

    static func decode(_ details: String) -> Payload {
        var payload = Payload()
        guard !details.isEmpty else { return payload }

        if !details.contains(";"), details.hasPrefix("dropoff_radius_meters=") {
            payload.dropOffRadiusMeters = Double(details.dropFirst("dropoff_radius_meters=".count))
            return payload
        }

        for part in details.split(separator: ";") {
            let segment = String(part)
            if segment.hasPrefix("dropoff_radius_meters=") {
                payload.dropOffRadiusMeters = Double(segment.dropFirst("dropoff_radius_meters=".count))
            } else if segment.hasPrefix("packages_total=") {
                payload.packageCount = Int(segment.dropFirst("packages_total=".count))
            } else if segment.hasPrefix("packages_max=") {
                payload.maxPackagesPerBooking = Int(segment.dropFirst("packages_max=".count))
            } else if segment.hasPrefix("packages_remaining=") {
                payload.packagesRemaining = Int(segment.dropFirst("packages_remaining=".count))
            }
        }
        return payload
    }

    static func encode(dropOffRadiusMeters: Double?) -> String {
        encode(Payload(dropOffRadiusMeters: dropOffRadiusMeters, packageCount: nil, maxPackagesPerBooking: nil, packagesRemaining: nil))
    }

    static func dropOffRadiusMeters(from details: String) -> Double? {
        decode(details).dropOffRadiusMeters
    }
}
