import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct NativeAppleSignIn: View {
    let account: CloudAccountController
    @State private var nonce: String?
    var body: some View {
        SignInWithAppleButton(.continue) { request in
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                nonce = nil; account.error = "Unable to prepare secure sign-in. Try again."; return
            }
            let raw = Data(bytes).base64EncodedString()
            nonce = raw
            request.nonce = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
            request.requestedScopes = [.email]
        } onCompletion: { result in
            let raw = nonce; nonce = nil
            switch result {
            case .success(let authorization):
                guard let raw, let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                    account.error = "Apple did not return a valid identity token. Try again."; return
                }
                Task { await account.signInWithApple(idToken: token, nonce: raw) }
            case .failure(let error):
                if (error as NSError).code != ASAuthorizationError.canceled.rawValue { account.error = error.localizedDescription }
            }
        }
        .frame(height: 44)
        .disabled(!account.configured || account.busy)
    }
}
