import Foundation
import UIKit

/// The apps Jimmy can import from, each with the lowest-effort path it allows. See
/// `docs/research/onboarding-import.md` for what each one exports and why.
enum ImportSource: String, CaseIterable, Identifiable, Hashable {
    case applePodcasts
    case spotify
    case overcast
    case pocketCasts
    case castro
    case otherApp

    var id: Self { self }

    var name: String {
        switch self {
        case .applePodcasts: "Apple Podcasts"
        case .spotify: "Spotify"
        case .overcast: "Overcast"
        case .pocketCasts: "Pocket Casts"
        case .castro: "Castro"
        case .otherApp: "Another App"
        }
    }

    /// What comes over, for the source list.
    var carries: String {
        switch self {
        case .applePodcasts: "Shows"
        case .spotify: "Shows, saved episodes and progress"
        case .overcast: "Shows, played episodes and progress"
        case .pocketCasts: "Shows"
        case .castro: "Shows"
        case .otherApp: "Shows, from an OPML file"
        }
    }

    /// How it gets here, shown on the source's screen.
    var summary: String {
        switch self {
        case .applePodcasts:
            "Apple Podcasts has no export, so Jimmy brings a shortcut that reads the shows you follow "
                + "and hands them back here."
        case .spotify where SpotifyConfig.isConfigured:
            "Sign in once and Jimmy adds your saved shows, then puts your saved episodes in the Queue "
                + "where you left off."
        case .spotify:
            "Spotify can send you a copy of your library. Jimmy adds your saved shows and puts your "
                + "saved episodes in the Queue."
        case .overcast:
            "Overcast's website exports your shows with every played episode and where you stopped, in one file."
        case .pocketCasts:
            "Pocket Casts exports your shows as an OPML file."
        case .castro:
            "Castro exports your shows as an OPML file."
        case .otherApp:
            "Most podcast apps can export an OPML file. Look for Export or OPML in the app's settings."
        }
    }

    /// The exact steps in the other app, ending with the file or clipboard in Jimmy's hands.
    var steps: [String] {
        switch self {
        case .applePodcasts:
            [
                "Tap Add Shortcut, choose Shortcuts, then tap Add Shortcut.",
                "Tap Move Podcasts to Jimmy and allow it to use Podcasts.",
                "Jimmy opens and adds every show you follow."
            ]
        case .spotify:
            [
                "On spotify.com, open Account, then Privacy Settings.",
                "Under Download Your Data, tick Account Data and tap Request Data.",
                "When Spotify emails you (up to 5 days), download and unzip the file.",
                "Tap Choose Files and pick YourLibrary.json and any StreamingHistory_podcast files."
            ]
        case .overcast:
            [
                "In Safari, go to overcast.fm/account and sign in.",
                "Under Export Your Data, tap All Data.",
                "Tap Download, so the file lands in Files.",
                "Come back and tap Choose File."
            ]
        case .pocketCasts:
            [
                "Open Pocket Casts and go to the Profile tab.",
                "Tap Settings, then Import & Export OPML.",
                "Tap Save File and save it to Files, or share it to Jimmy.",
                "Come back and tap Choose File."
            ]
        case .castro:
            [
                "Open Castro and tap Settings.",
                "Tap User Data, then Export Subscriptions.",
                "Save the file to Files, or share it to Jimmy.",
                "Come back and tap Choose File."
            ]
        case .otherApp:
            [
                "In your podcast app's settings, find Export, Export OPML or Backup.",
                "Save the file to Files, or share it to Jimmy.",
                "Come back and tap Choose File."
            ]
        }
    }

    /// The app's URL scheme, to tell whether it's on this iPhone. Listed in
    /// `LSApplicationQueriesSchemes`.
    private var scheme: String? {
        switch self {
        case .applePodcasts: "podcasts"
        case .spotify: "spotify"
        case .overcast: "overcast"
        case .pocketCasts: "pktc"
        case .castro: "castro"
        case .otherApp: nil
        }
    }

    /// Where the steps start: the app, Shortcuts for Apple Podcasts, Overcast's website.
    var startURL: URL? {
        switch self {
        case .applePodcasts: ApplePodcastsShortcut.runURL
        case .overcast: URL(string: "https://overcast.fm/account")
        default: scheme.flatMap { URL(string: "\($0)://") }
        }
    }

    var startTitle: String {
        switch self {
        case .applePodcasts: "Run Shortcut Again"
        case .overcast: "Open overcast.fm"
        default: "Open \(name)"
        }
    }

    /// Whether the app is on this iPhone.
    @MainActor
    var isInstalled: Bool {
        guard let url = scheme.flatMap({ URL(string: "\($0)://") }) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Sources in the order the start screen shows them, apps on this iPhone first.
    @MainActor
    static func ordered() -> (installed: [ImportSource], others: [ImportSource]) {
        let installed = allCases.filter(\.isInstalled)
        return (installed, allCases.filter { !installed.contains($0) })
    }
}

/// "Move Podcasts to Jimmy": Get Podcasts from Library, then each show's Store ID, opened as
/// `jimmy://import?text=…`. Built and signed by `Tools/shortcut/build.sh`.
enum ApplePodcastsShortcut {
    static let name = "Move Podcasts to Jimmy"

    /// The signed shortcut in the app bundle, shared into Shortcuts.
    static var fileURL: URL? {
        Bundle.main.url(forResource: name, withExtension: "shortcut")
    }

    /// Runs it once it's been added.
    static var runURL: URL? {
        var components = URLComponents(string: "shortcuts://run-shortcut")
        components?.queryItems = [URLQueryItem(name: "name", value: name)]
        return components?.url
    }
}
