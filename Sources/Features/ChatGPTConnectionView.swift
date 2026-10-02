import SwiftUI
import ChatGPTAuth
import DesignSystem
#if os(iOS)
import SafariServices
#elseif os(macOS)
import AppKit
#endif

struct ChatGPTConnectionView: View {
    @Bindable var connection: ChatGPTConnection
    @State private var browser: ChatGPTBrowserDestination?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: EngramSpacing.regular) {
            if let account = connection.activeAccount {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark").font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ChatGPT").font(.headline)
                        Text(account.label).font(.subheadline).foregroundStyle(theme.palette(for: scheme).secondaryText)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.palette(for: scheme).accentInk)
                }
                Text(account.planUsageEnabled ? "ChatGPT plan usage enabled" : "Connected · plan usage not granted")
                    .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                Button("Sign out of ChatGPT") { Task { await connection.signOut() } }
                    .buttonStyle(.bordered).disabled(connection.busy)
            }
            ForEach(connection.registrations) { account in
                if account.clientID != connection.activeClientID {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.label)
                            // Client suffix distinguishes separate registrations/workspaces with the same email.
                            Text("Connection …" + String(account.clientID.suffix(8)))
                                .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                        }
                        Spacer()
                        Button(account.credentials == nil ? "Reconnect" : "Use account") {
                            if account.credentials == nil { signIn(account.clientID) }
                            else { connection.selectAccount(account.clientID) }
                        }.buttonStyle(.bordered).disabled(connection.busy)
                    }
                }
            }
            if connection.busy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(connection.signingIn ? "Finish sign-in in the browser…" : "Updating connection…")
                    Spacer()
                    if connection.signingIn { Button("Cancel") { connection.cancelSignIn(); browser = nil } }
                }
            } else {
                Button { signIn(nil) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                        Text(connection.activeAccount == nil ? "Continue with ChatGPT" : "Connect another account")
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                    }.frame(minHeight: 26)
                }.buttonStyle(EngramButtonStyle(.secondary))
                if let account = connection.activeAccount, !account.planUsageEnabled {
                    Button("Authorize ChatGPT plan usage") { signIn(account.clientID) }.buttonStyle(.bordered)
                }
            }
            Text("Connect your AI account separately from Engram sync. Eligible accounts can grant plan usage; requests share your ChatGPT limits. Engram cannot access your ChatGPT conversations.")
                .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
            Text("AI answer marking can use this connection when you enable it. Audio is processed on your device.")
                .font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
            HStack {
                Link("Manage usage", destination: ChatGPTOAuth.usageURL)
                Link("Manage app access", destination: ChatGPTOAuth.accessURL)
            }.font(theme.font(.metadata))
            if let error = connection.error { EngramInlineError(message: error) }
            if let notice = connection.notice { Text(notice).font(theme.font(.metadata)).accessibilityLabel(notice) }
        }
        .alert("You're using your ChatGPT plan", isPresented: $connection.showPlanConfirmation) {
            Button("Got it") { connection.acknowledgePlanUsage() }
        } message: {
            Text("Enabled AI answer marking uses your ChatGPT plan. You can manage Engram's access and usage limits in ChatGPT settings.")
        }
        #if os(iOS)
        .sheet(item: $browser, onDismiss: { if connection.waitingForBrowser { connection.cancelSignIn() } }) { destination in
            ChatGPTSignInBrowser(url: destination.url, finished: {
                if connection.waitingForBrowser { connection.cancelSignIn() }
                browser = nil
            }).ignoresSafeArea()
        }
        #endif
        .onChange(of: connection.busy) { _, busy in if !busy { browser = nil } }
        .onChange(of: connection.waitingForBrowser) { _, waiting in if !waiting { browser = nil } }
        .onDisappear { connection.cancelSignIn() }
    }

    private func signIn(_ clientID: String?) {
        connection.signIn(registrationID: clientID) { url in
            #if os(iOS)
            // A Safari-controlled sheet keeps Engram foregrounded for its loopback listener.
            browser = ChatGPTBrowserDestination(url: url)
            #elseif os(macOS)
            guard NSWorkspace.shared.open(url) else { throw ChatGPTAuthError.browserUnavailable }
            #endif
        }
    }
}

private struct ChatGPTBrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
private struct ChatGPTSignInBrowser: UIViewControllerRepresentable {
    let url: URL
    let finished: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let finished: () -> Void
        init(finished: @escaping () -> Void) { self.finished = finished }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { finished() }
    }
}
#endif
