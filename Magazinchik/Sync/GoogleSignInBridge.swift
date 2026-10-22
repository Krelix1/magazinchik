import FirebaseAuth
import GoogleSignIn
import UIKit

enum GoogleSignInBridgeError: Error {
    case unavailable
}

/// Presents Google sign-in and turns the result into a Firebase credential. The same uid then owns the cards.
@MainActor
enum GoogleSignInBridge {
    static func credential(clientID: String) async throws -> AuthCredential {
        guard let presenter = topViewController() else { throw GoogleSignInBridgeError.unavailable }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await signIn(presenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else { throw GoogleSignInBridgeError.unavailable }
        return GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
    }

    static func handle(_ url: URL) {
        guard GoogleSignInConfig.current != nil else { return }
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    static func isCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.Code.canceled.rawValue
    }

    private static func signIn(presenting presenter: UIViewController) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: GoogleSignInBridgeError.unavailable)
                }
            }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let root = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
