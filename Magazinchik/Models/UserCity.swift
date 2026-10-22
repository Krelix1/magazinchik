import Foundation
import SwiftData

/// A real area, not a bare name. Store search uses the box; the name is only what the person sees.
struct BoundingBox: Sendable, Equatable {
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLatitude && latitude <= maxLatitude && longitude >= minLongitude && longitude <= maxLongitude
    }
}

/// One city the person picked. `id` is assigned when it is saved.
struct UserCity: Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var box: BoundingBox
}

/// A Nominatim hit before it is saved. The box is the area later sent to OpenStreetMap.
struct CityMatch: Sendable, Identifiable, Equatable {
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double
    var box: BoundingBox

    var id: String { "\(latitude),\(longitude),\(name)" }
}

@Model
final class CityRecord {
    var id: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var minLatitude: Double = 0
    var maxLatitude: Double = 0
    var minLongitude: Double = 0
    var maxLongitude: Double = 0
    var isActive: Bool = false

    init(name: String, latitude: Double, longitude: Double, box: BoundingBox, isActive: Bool = false) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.minLatitude = box.minLatitude
        self.maxLatitude = box.maxLatitude
        self.minLongitude = box.minLongitude
        self.maxLongitude = box.maxLongitude
        self.isActive = isActive
    }

    var box: BoundingBox {
        BoundingBox(minLatitude: minLatitude, maxLatitude: maxLatitude, minLongitude: minLongitude, maxLongitude: maxLongitude)
    }

    var city: UserCity {
        UserCity(id: id, name: name, latitude: latitude, longitude: longitude, box: box)
    }
}

/// Stores of one brand inside one city. Kept when the person switches city, so coming back does not download them again.
@Model
final class CachedBrandStore {
    var id: UUID = UUID()
    var brandKey: String = ""
    var cityID: UUID = UUID()
    var name: String = ""
    var address: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var fetchedAt: Date = Date()
    /// False on lists saved while the app kept only the first 50 matches. Those are fetched again.
    var isFullCityList: Bool = false

    init(brandKey: String, cityID: UUID, name: String, address: String, latitude: Double, longitude: Double, fetchedAt: Date = .now, isFullCityList: Bool = true) {
        self.id = UUID()
        self.brandKey = brandKey
        self.cityID = cityID
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.fetchedAt = fetchedAt
        self.isFullCityList = isFullCityList
    }
}

@MainActor
enum CityStore {
    /// Makes this area the one new cards are filled from. Other cities stay saved.
    static func activate(_ match: CityMatch, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<CityRecord>())) ?? []
        let same = all.first { record in
            CardText.normalizedName(record.name) == CardText.normalizedName(match.name)
                && abs(record.latitude - match.latitude) < 0.2
                && abs(record.longitude - match.longitude) < 0.2
        }
        for record in all {
            record.isActive = false
        }
        if let same {
            same.isActive = true
        } else {
            context.insert(CityRecord(name: match.name, latitude: match.latitude, longitude: match.longitude, box: match.box, isActive: true))
        }
        try? context.save()
    }
}
