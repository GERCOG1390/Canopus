import SwiftUI
import EVEAuth
import AuthenticationServices

struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.webAuthenticationSession) private var webAuthSession
    @State private var isAuthenticating = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Add a Character")
                    .font(.title.bold())
                Text("Sign in with EVE Online to view your\nskill queue, wallet, and more.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await addCharacter() }
            } label: {
                Group {
                    if isAuthenticating {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Label("Sign in with EVE Online", systemImage: "person.badge.key")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
            .padding(.horizontal, 32)

            Spacer()
        }
        .alert("Authentication Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    private func addCharacter() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await env.characterStore.addCharacter { authURL in
                try await webAuthSession.authenticate(
                    using: authURL,
                    callbackURLScheme: EVEConstants.callbackScheme
                )
            }
        } catch let err as ASWebAuthenticationSessionError where err.code == .canceledLogin {
            // user tapped Cancel — no error shown
        } catch AuthError.cancelled {
            // auth cancelled — no error shown
        } catch {
            self.error = error
        }
    }
}
