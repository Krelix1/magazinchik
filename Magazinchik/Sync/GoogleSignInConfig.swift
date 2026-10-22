import Foundation

struct GoogleClientIDs: Equatable, Sendable {
    var clientID: String
    var reversedClientID: String
}

/// Client ids from `GoogleService-Info.plist`. Placeholders and a missing plist mean Google sign-in stays off.
enum GoogleSignInConfig {
    static func read(from values: [String: String]) -> GoogleClientIDs? {
        guard let clientID = usable(values["CLIENT_ID"]),
              let reversedClientID = usable(values["REVERSED_CLIENT_ID"]) else { return nil }
        return GoogleClientIDs(clientID: clientID, reversedClientID: reversedClientID)
    }

    static func read(plist url: URL) -> GoogleClientIDs? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        var values: [String: String] = [:]
        for (key, value) in object {
            if let string = value as? String {
                values[key] = string
            }
        }
        return read(from: values)
    }

    static var current: GoogleClientIDs? {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") else { return nil }
        return read(plist: url)
    }

    private static func usable(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("YOUR_") else { return nil }
        return value
    }
}
