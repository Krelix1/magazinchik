import Foundation

/// The location button. The card list updates from the latest fix and the saved stores before any network call.
@MainActor
@Observable
final class PlaceRefresh {
    /// True only during the short location read. A store lookup does not keep this set.
    private(set) var isRunning = false
    /// Bumped when the on-screen fix should be ranked again, without the previous sticky card.
    private(set) var revision = 0

    /// Reads a fresh fix and asks the screen to rank the saved coordinates again. It does not call OpenStreetMap.
    func runManual(location: LocationService) async {
        guard !isRunning else { return }
        isRunning = true
        let already = location.latestFix
        if let already {
            location.adopt(already)
            revision += 1
        }
        let fresh = await location.nextFix(since: Date().addingTimeInterval(-5), timeout: .seconds(1))
        isRunning = false
        if let fresh, fresh.timestamp != already?.timestamp {
            location.adopt(fresh)
            revision += 1
        } else if already == nil {
            revision += 1
        }
    }
}
