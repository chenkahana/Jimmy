import AuthenticationServices
import JimmyKit
import SwiftUI
import UniformTypeIdentifiers

enum OnboardingRoute: Hashable {
    case source(ImportSource)
    case progress
}

/// The first-run screen: where the listener's podcasts are now, and one tap toward bringing
/// them over. Also opened from Settings > Import from Another App, and by sharing a file to Jimmy.
struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Bindable private var onboarding = Onboarding.shared
    @State private var path: [OnboardingRoute] = []
    @State private var sources = ImportSource.ordered()
    @State private var isChoosingFile = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Text("Bring your shows, played episodes and progress from the app you use now.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

                if !sources.installed.isEmpty {
                    Section("On This iPhone") {
                        ForEach(sources.installed) { SourceRow(source: $0) }
                    }
                }
                Section(sources.installed.isEmpty ? "Import From" : "Other Apps") {
                    ForEach(sources.others) { SourceRow(source: $0) }
                }
                Section {
                    Button("Browse Top Shows") { finish(to: .discover()) }
                } header: {
                    Text("Start Fresh")
                } footer: {
                    Text("You can import later from Settings.")
                }
            }
            .navigationTitle("Welcome to Jimmy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish(to: .library) }
                }
            }
            .safeAreaInset(edge: .bottom) { primaryButton }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: ImportFileTypes.all, allowsMultipleSelection: true) { result in
                if case .success(let files) = result { startImport(files: files) }
            }
            .navigationDestination(for: OnboardingRoute.self) { route in
                switch route {
                case .source(let source):
                    ImportSourceView(source: source, onStart: start)
                case .progress:
                    ImportProgressView(session: onboarding.session, onFinish: finish, onRetry: retry)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            sources = ImportSource.ordered()
            if !onboarding.pendingFiles.isEmpty {
                let files = onboarding.pendingFiles
                onboarding.pendingFiles = []
                startImport(files: files)
            } else if onboarding.session.phase != .idle {
                path = [.progress]
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        Group {
            if let source = sources.installed.first {
                Button("Import from \(source.name)") { path.append(.source(source)) }
            } else {
                Button("Choose an Export File") { isChoosingFile = true }
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, JimmyDesign.Spacing.lg)
        .padding(.bottom, JimmyDesign.Spacing.sm)
    }

    private func startImport(files: [URL]) {
        start { session, model in await session.run(files: files, model: model) }
    }

    /// Pushes the progress screen and runs `work` on a fresh session. The import keeps going if
    /// the listener leaves before it finishes.
    private func start(_ work: @escaping @MainActor (LibraryImportSession, AppModel) async -> Void) {
        onboarding.startOver()
        let session = onboarding.session
        let model = appModel
        path = [.progress]
        Task { await work(session, model) }
    }

    private func retry() {
        onboarding.startOver()
        path.removeAll()
    }

    private func finish(to destination: ShellDestination) {
        onboarding.finish()
        dismiss()
        ShellStore.shared.sheet = nil
        ShellStore.shared.navigate(to: destination)
    }
}

/// File types an export can come in. Most apps write `.opml`; some share it as XML or text.
enum ImportFileTypes {
    static let opml = UTType(filenameExtension: "opml", conformingTo: .xml) ?? .xml
    static let all: [UTType] = [opml, .xml, .json, .plainText, .commaSeparatedText]
}

private struct SourceRow: View {
    let source: ImportSource

    var body: some View {
        NavigationLink(value: OnboardingRoute.source(source)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                Text(source.carries)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - One source

/// One app's steps, ending in the action that hands Jimmy the file, the clipboard or a sign-in.
struct ImportSourceView: View {
    let source: ImportSource
    let onStart: (@escaping @MainActor (LibraryImportSession, AppModel) async -> Void) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isChoosingFile = false
    @State private var signInError: String?

    var body: some View {
        List {
            Section {
                Text(source.summary)
            } footer: {
                if source == .spotify {
                    Text("Shows only on Spotify have no public feed, so they can't come over.")
                }
            }

            if source == .spotify, SpotifyConfig.isConfigured {
                Section {
                    Button("Sign In with Spotify") { Task { await signInWithSpotify() } }
                } footer: {
                    if let signInError { Text(signInError) }
                }
            }

            Section(stepsHeader) {
                ForEach(Array(source.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: JimmyDesign.Spacing.md) {
                        Text("\(index + 1)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(step)
                    }
                }
            }

            if let startURL = source.startURL, source.isInstalled || source == .overcast || source == .applePodcasts {
                Section {
                    Button(source.startTitle) { openURL(startURL) }
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { primaryAction }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: ImportFileTypes.all, allowsMultipleSelection: true) { result in
            guard case .success(let files) = result else { return }
            onStart { session, model in await session.run(files: files, model: model) }
        }
    }

    private var stepsHeader: String {
        source == .spotify && SpotifyConfig.isConfigured ? "Without Signing In" : "Steps"
    }

    @ViewBuilder
    private var primaryAction: some View {
        Group {
            if source == .applePodcasts {
                PasteButton(payloadType: String.self) { strings in
                    let text = strings.joined(separator: "\n")
                    onStart { session, model in await session.run(pastedText: text, model: model) }
                }
                .labelStyle(.titleAndIcon)
            } else if source == .spotify, SpotifyConfig.isConfigured {
                Button("Choose Files") { isChoosingFile = true }
                    .buttonStyle(.glass)
            } else {
                Button(source == .spotify ? "Choose Files" : "Choose File") { isChoosingFile = true }
                    .buttonStyle(.glassProminent)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, JimmyDesign.Spacing.lg)
        .padding(.bottom, JimmyDesign.Spacing.sm)
    }

    private func signInWithSpotify() async {
        guard let api = SpotifyConfig.api() else { return }
        let verifier = SpotifyWebAPI.makeCodeVerifier()
        let state = UUID().uuidString
        guard let url = api.authorizationURL(codeChallenge: SpotifyWebAPI.codeChallenge(for: verifier), state: state) else { return }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: url,
                callback: .customScheme(SpotifyConfig.callbackScheme),
                preferredBrowserSession: .shared,
                additionalHeaderFields: [:]
            )
            guard let code = api.authorizationCode(from: callback, expectedState: state) else {
                signInError = "Spotify didn't confirm the sign-in. Try again."
                return
            }
            onStart { session, model in
                await session.run(fetching: {
                    let token = try await api.accessToken(code: code, codeVerifier: verifier)
                    return try await api.library(accessToken: token)
                }, model: model)
            }
        } catch {
            // Cancelled in the sign-in sheet: stay on this screen.
        }
    }
}

/// Spotify sign-in is on when the build sets `SPOTIFY_CLIENT_ID` (an app registered at
/// developer.spotify.com with the redirect URI `jimmy://spotify-callback`).
enum SpotifyConfig {
    static let callbackScheme = "jimmy"
    static let redirectURI = URL(string: "jimmy://spotify-callback")

    static var clientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static var isConfigured: Bool { clientID != nil }

    static func api() -> SpotifyWebAPI? {
        guard let clientID, let redirectURI else { return nil }
        return SpotifyWebAPI(clientID: clientID, redirectURI: redirectURI)
    }
}
