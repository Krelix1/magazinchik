import FirebaseCore
import FirebaseFirestore
import Foundation

/// Starts Firebase only when the real client plist is in the app bundle.
/// Without it the wallet stays on the phone and nothing here touches the network.
enum FirebaseGate {
    private(set) static var isConfigured = false

    static func configureIfPresent() {
        guard !isConfigured else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        let firestore = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        firestore.settings = settings
        isConfigured = true
    }
}
