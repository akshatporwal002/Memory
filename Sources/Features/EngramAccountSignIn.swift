import SwiftUI
import DesignSystem
import ChatGPTAuth
import CloudAdapters
#if os(macOS)
import AppKit
#endif

struct EngramAccountSignIn: View {
    let model: EngramModel
    var linkingAIOnly = false
    var compact = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var emailExpanded = false
    @State private var email = ""
    @State private var code = ""
    @State private var browser: ChatGPTBrowserDestination?
    @State private var choosingChatGPT = false
    @State private var attemptedChatGPT = false
    private var palette: EngramPalette { theme.palette(for: scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !linkingAIOnly && !compact { VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Engram").font(.title2.weight(.semibold))
                Text("A home for everything you learn.").font(.subheadline).foregroundStyle(palette.secondaryText)
            } }
            VStack(spacing: 10) {
                if let account = model.chatGPT.activeAccount {
                    NavigationLink { ChatGPTManagementPage(model: model) } label: {
                        Text("Manage ChatGPT").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(AccountOutlineButton()).accessibilityIdentifier("account-manage-chatgpt")
                    Text(account.label).font(.caption).foregroundStyle(palette.secondaryText).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                Button {
                    choosingChatGPT = true
                    attemptedChatGPT = true
                    model.chatGPT.signIn(registrationID: model.chatGPT.activeClientID) { url in
                        #if os(iOS)
                        browser = ChatGPTBrowserDestination(url: url)
                        #else
                        guard NSWorkspace.shared.open(url) else { throw ChatGPTAuthError.browserUnavailable }
                        #endif
                    }
                } label: {
                    Label("Continue with ChatGPT", systemImage: "sparkle").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(AccountOutlineButton()).disabled(model.chatGPT.busy || model.cloud.busy)
                    .accessibilityIdentifier("account-chatgpt")
                }
                if !linkingAIOnly { VStack(spacing: 10) {
                if hasIdentity("google") {
                    manageLink("google")
                } else {
                Button { Task {
                    await model.cloud.signIn("google")
                } } label: {
                    Text("Continue with Google").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(AccountOutlineButton()).disabled(!model.cloud.configured).accessibilityIdentifier("account-google")
                }
                if hasIdentity("apple") { manageLink("apple") } else {
                NativeAppleSignIn(account: model.cloud)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("account-apple")
                if !model.cloud.appleSignInEnabled { Text("Apple sign-in is awaiting setup.").font(.caption).foregroundStyle(palette.secondaryText) }
                }
                if hasIdentity("email") { manageLink("email") } else {
                Button { withAnimation(.easeInOut(duration: 0.2)) { emailExpanded.toggle() } } label: {
                    Label("Continue with Email", systemImage: "envelope").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(AccountOutlineButton()).accessibilityIdentifier("account-email")
                }
                }.disabled(model.cloud.busy || model.chatGPT.busy) }
            }
            if emailExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if let address = model.cloud.emailCodeAddress {
                        Text("Enter the code sent to \(address)").font(.subheadline).foregroundStyle(palette.secondaryText)
                        TextField("Verification code", text: $code).textContentType(.oneTimeCode)
                            .accountField(palette: palette)
                            .onSubmit { Task { await model.cloud.verifyEmailCode(code) } }
                        Button(model.cloud.userID != nil ? "Confirm email" : "Sign in") { Task { await model.cloud.verifyEmailCode(code) } }.buttonStyle(AccountOutlineButton()).frame(minHeight: 44)
                        HStack {
                            Button("Use another email") { code = ""; model.cloud.changeEmail() }
                            Spacer()
                            Button("Resend code") { Task { await model.cloud.sendEmailCode(address) } }
                        }.font(.caption).frame(minHeight: 44)
                    } else {
                        Text("Email").font(.subheadline.weight(.medium))
                        TextField("you@example.com", text: $email).textContentType(.emailAddress)
                            .accountField(palette: palette)
                            .onSubmit { Task { await model.cloud.sendEmailCode(email) } }
                        Button("Send verification code") { Task { await model.cloud.sendEmailCode(email) } }
                            .buttonStyle(AccountOutlineButton()).frame(minHeight: 44)
                        Text(model.cloud.userID != nil ? "Add or replace this account's email login. Confirm ownership to keep your libraries on the same account." : "No password needed. Your first sign-in creates an account.").font(.caption).foregroundStyle(palette.secondaryText)
                    }
                }.disabled(model.cloud.busy || !model.cloud.configured)
            }
            if !linkingAIOnly && !compact { Button("Continue without an account") { dismiss() }.font(.subheadline).foregroundStyle(palette.secondaryText).frame(maxWidth: .infinity, minHeight: 44) }
            if !model.cloud.configured {
                Text("Cloud sign-in is awaiting setup. You can keep studying locally.").font(.caption).foregroundStyle(palette.secondaryText)
            }
            if attemptedChatGPT, let error = model.chatGPT.error { Text(error).font(.footnote).foregroundStyle(palette.againInk).accessibilityLabel("Sign-in error: " + error) }
            if model.chatGPT.busy { ProgressView("Connecting to ChatGPT…") }
        }.padding(.vertical, 20).frame(maxWidth: 400).frame(maxWidth: .infinity)
            .listRowBackground(palette.canvas).listRowSeparator(.hidden)
            .onChange(of: model.chatGPT.busy) { _, busy in
                guard !busy, choosingChatGPT else { return }
                browser = nil; choosingChatGPT = false
                if !linkingAIOnly, !model.cloud.signedIn, model.chatGPT.error == nil, model.chatGPT.notice != "Sign-in cancelled.", let account = model.chatGPT.activeAccount, account.credentials != nil { model.cloud.pendingChatGPTProfile = account }
            }
            .onChange(of: model.chatGPT.waitingForBrowser) { _, waiting in if !waiting { browser = nil } }
            .alert("You're using your ChatGPT plan", isPresented: Binding(get: { model.chatGPT.showPlanConfirmation }, set: { if !$0 { model.chatGPT.acknowledgePlanUsage() } })) {
                Button("Got it") { model.chatGPT.acknowledgePlanUsage() }
            } message: { Text("Eligible AI requests use your ChatGPT plan and share its usage limits. You can manage access in ChatGPT settings.") }
            #if os(iOS)
            .sheet(item: $browser, onDismiss: { if model.chatGPT.waitingForBrowser { model.chatGPT.cancelSignIn() } }) { destination in
                ChatGPTSignInBrowser(url: destination.url, finished: {
                    if model.chatGPT.waitingForBrowser { model.chatGPT.cancelSignIn() }
                    browser = nil
                }).ignoresSafeArea()
            }
            #endif
    }
    private func hasIdentity(_ provider: String) -> Bool { model.cloud.loginIdentities.contains { $0.provider == provider } }
    private func manageLink(_ provider: String) -> some View {
        NavigationLink { LoginMethodManagementPage(model: model, provider: provider) } label: {
            Text(AppLoginIdentity.buttonTitle(provider: provider, identities: model.cloud.loginIdentities))
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
        }.buttonStyle(AccountOutlineButton()).accessibilityIdentifier("account-manage-" + provider)
    }
}

private struct LoginMethodManagementPage: View {
    let model: EngramModel
    let provider: String
    @State private var removing: AppLoginIdentity?
    @State private var confirmSignOut = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            EngramListSection {
                ForEach(model.cloud.loginIdentities.filter { $0.provider == provider }) { identity in
                    Label(identity.email ?? provider.capitalized + " connected", systemImage: "checkmark.circle")
                    if provider != "email" {
                        Button("Remove " + provider.capitalized + " login", role: .destructive) { removing = identity }
                            .disabled(model.cloud.loginIdentities.count < 2 || model.cloud.busy)
                    }
                }
            } footer: { Text("This login opens your Engram account and its libraries. All linked login methods share one Engram session.") }
            if provider == "email" { Text("Email is your account's contact and verified email login. It cannot be disconnected here.").font(.caption).engramSecondaryText() }
            Button("Sign out of Engram", role: .destructive) { confirmSignOut = true }
            Text("Signs out of the shared Google, Apple and email session on this device. Your ChatGPT AI connection remains connected.").font(.caption).engramSecondaryText()
            if let error = model.cloud.error { EngramInlineError(message: error) }
        }.modifier(UtilityListStyle()).navigationTitle("Manage " + (provider == "email" ? "Email" : provider.capitalized))
            .confirmationDialog("Remove this login method?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                if let identity = removing { Button("Remove login", role: .destructive) { Task { await model.cloud.removeLoginIdentity(identity); removing = nil; if model.cloud.error == nil { dismiss() } } } }
            } message: { Text("You can continue signing in using another linked method. Your library is preserved.") }
            .confirmationDialog("Sign out of Engram on this device?", isPresented: $confirmSignOut) {
                Button("Sign out of Engram", role: .destructive) { Task { await model.cloud.signOut(model: model); if !model.cloud.signedIn { dismiss() } } }
            }
    }
}

private struct AccountOutlineButton: ButtonStyle {
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let palette = theme.palette(for: scheme)
        configuration.label.frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(palette.primaryText)
            .background(configuration.isPressed ? palette.selection : palette.surface, in: Capsule())
    }
}

private extension View {
    func accountField(palette: EngramPalette) -> some View {
        self.autocorrectionDisabled().padding(12).frame(minHeight: 48)
            .background(palette.canvas)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.hairline).frame(height: 1) }
    }
}
