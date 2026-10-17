// food listing

import Foundation
import SwiftData
import CoreLocation
import SwiftUI

@Model
final class FoodListing {
    var title: String
    var details: String
    var quantity: String
    // keeps old data working when we add fields
    var categoryRaw: String = FoodCategory.mixed.rawValue
    var quantitySizeRaw: String = QuantitySize.feeds3to5.rawValue
    var pickupTypeRaw: String = PickupType.meetOutside.rawValue
    // rough neighborhood label for the map
    var area: String = ""
    @Attribute(.externalStorage) var photo: Data?
    // online photo link once it is synced
    var photoURL: String?
    var pickupAddress: String
    var latitude: Double
    var longitude: Double
    var pickupDeadline: Date
    var pickupNotes: String?
    var contactInstructions: String?
    var statusRaw: String
    var moderationStatusRaw: String = "pending"
    var moderationReason: String?
    var createdAt: Date
    // online row id when synced
    var remoteID: String?
    var postedByDeviceID: String
    var claimedByDeviceID: String?
    // when the hold ends it opens back up
    var reservedUntil: Date?
    // folks waiting for it to reopen
    var waitlistDeviceIDs: [String] = []
    // how far the donor will drive for dropoff
    var dropOffRadiusMeters: Double?
    // how many packs were listed in total
    var packageCount: Int = 0
    // most packs one person can grab at once
    var maxPackagesPerBooking: Int = 0
    // packs still left to grab
    var packagesRemaining: Int = 0
    // pantry post, not a neighbor post
    var pantryGCFDLocationID: Int?
    // shop entries that always stay in the list
    var isPermanent: Bool = false

    // shop posts use this id so they look different
    static let permanentPosterID = "shareplate.permanent-store"

    // short hold at first, longer once booked
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
        packagesRemaining: Int = 0,
        pantryGCFDLocationID: Int? = nil,
        isPermanent: Bool = false,
        moderationStatus: String = "pending",
        moderationReason: String? = nil
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
        self.pantryGCFDLocationID = pantryGCFDLocationID
        self.isPermanent = isPermanent
        self.moderationStatusRaw = moderationStatus
        self.moderationReason = moderationReason
        if packageCount == 0 {
            syncPackageFieldsFromDetails()
        }
    }

    // typed helpers

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

    // short code so you can talk about a post easily
    var listingNumber: String {
        guard let remoteID, let uuid = UUID(uuidString: remoteID) else { return "—" }
        return "#" + uuid.uuidString.prefix(6).uppercased()
    }

    var isPantryListing: Bool { pantryGCFDLocationID != nil }

    var isApprovedForSharing: Bool { moderationStatusRaw == "approved" }

    var moderationLabel: String {
        if isExpired, moderationStatusRaw == "pending" { return String(localized: "Expired") }
        return moderationStatusRaw == "rejected"
            ? String(localized: "Not approved")
            : String(localized: "Awaiting review")
    }

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
// old posts had no left count so treat them as full
            if payload.packagesRemaining == nil, packagesRemaining == 0 {
                packagesRemaining = total
            }
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

    // packs left before the current hold
    var effectivePackagesRemaining: Int {
        if packageCount > 0 {
            return max(0, min(packagesRemaining, packageCount))
        }
        return hasActiveHandoff ? 0 : totalPackages
    }

    // packs in the current booking
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
        return count == 1 ? String(localized: "1 pack") : String(localized: "\(count) packs")
    }

    static func quantityLabel(packageCount: Int, maxPerBooking: Int) -> String {
        if maxPerBooking >= packageCount {
            return packageCount == 1 ? String(localized: "1 package") : String(localized: "\(packageCount) packages")
        }
        return String(localized: "\(packageCount) packages · max \(maxPerBooking) each")
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

    // pickup notes for booked handoffs
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

    // code stays hidden until someone books
    var revealsBookingCode: Bool {
        guard !isPermanent else { return false }
        switch effectiveStatus {
        case .reserved, .readyForPickup, .pickedUp:
            return true
        case .available, .expired:
            return false
        }
    }

    // short booking code shown on the dashboard
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

    // location helpers

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // fuzzy map spot so the address stays private
    var publicCoordinate: CLLocationCoordinate2D {
        func blur(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        return CLLocationCoordinate2D(latitude: blur(latitude), longitude: blur(longitude))
    }

    var areaLabel: String {
        area.isEmpty ? String(localized: "Nearby") : area
    }

    // timing helpers

    // demo spot that stays on the map a long time
    var isStandingLocation: Bool {
        !isPermanent && pickupDeadline.timeIntervalSinceNow > 60 * 60 * 24 * 180
    }

    var isExpired: Bool {
        if isPermanent || isStandingLocation { return false }
        return pickupDeadline < Date()
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
        if seconds < 60 { return String(localized: "Posted just now") }
        let minutes = seconds / 60
        if minutes < 60 { return String(localized: "Posted \(minutes) min ago") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "Posted \(hours)h ago") }
        return String(localized: "Posted \(hours / 24)d ago")
    }

    var expiresText: String {
        String(localized: "Expires \(pickupDeadline.formatted(date: .omitted, time: .shortened))")
    }

    // status helpers

    // booked handoffs can still finish after the deadline
    var hasActiveHandoff: Bool {
        guard claimedByDeviceID != nil else { return false }
        return status == .reserved || status == .readyForPickup
    }

    // what to show after checking dates and holds
    var effectiveStatus: ListingStatus {
        if status == .pickedUp { return .pickedUp }
        if hasActiveHandoff { return status }
        if packageCount > 0 && effectivePackagesRemaining == 0 { return .pickedUp }
        if isExpired { return .expired }
        if status == .reserved, let until = reservedUntil, until < Date() { return .available }
        return status
    }

    // multi pack posts reopen until packs run out
    var shouldReopenAfterHandoffCompletion: Bool {
        hasActiveHandoff && packageCount > 0 && effectivePackagesRemaining > 0
    }

    // same colors as the map key and badges
    var indicatorColor: Color {
        switch effectiveStatus {
        case .expired:
            return Theme.Palette.urgentRed
        case .pickedUp:
            return Theme.Palette.mutedText
        case .reserved:
            return ListingStatus.reserved.tint
        case .readyForPickup:
            return ListingStatus.readyForPickup.tint
        case .available:
            return mapOpenStatus.pinColor
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
