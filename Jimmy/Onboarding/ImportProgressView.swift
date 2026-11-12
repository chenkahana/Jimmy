import SwiftUI

/// The import as it runs — "Found 42 shows", each show's artwork arriving as it's added — and
/// then what came over, with one button into the filled Queue or Library.
struct ImportProgressView: View {
    let session: LibraryImportSession
    let onFinish: (ShellDestination) -> Void
    let onRetry: () -> Void

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: JimmyDesign.Spacing.sm) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                ForEach(details, id: \.self) { line in
                    Text(line)
                        .foregroundStyle(.secondary)
                }
                if session.isRunning {
                    ProgressView(value: fraction)
                        .padding(.top, JimmyDesign.Spacing.xs)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: JimmyDesign.Spacing.sm, leading: 20, bottom: JimmyDesign.Spacing.sm, trailing: 20
            ))
            .accessibilityElement(children: .combine)

            if !session.rows.isEmpty {
                Section {
                    ForEach(session.rows) { row in
                        if row.state == .notFound, session.phase == .finished {
                            Button { onFinish(.discover(query: row.title)) } label: {
                                ImportShowRow(row: row)
                            }
                            .tint(.primary)
                            .accessibilityHint("Searches for this show")
                        } else {
                            ImportShowRow(row: row)
                        }
                    }
                } footer: {
                    if session.notFoundCount > 0, session.phase == .finished {
                        Text("Tap a show that wasn't found to search for it.")
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!isFailed)
        .safeAreaInset(edge: .bottom) { bottomButton }
    }

    private var isFailed: Bool {
        if case .failed = session.phase { return true }
        return false
    }

    private var fraction: Double {
        switch session.phase {
        case .addingShows:
            session.rows.isEmpty ? 0 : Double(session.doneCount) / Double(session.rows.count) * 0.9
        case .importingHistory: 0.95
        default: 0.05
        }
    }

    private var headline: String {
        switch session.phase {
        case .idle, .reading: "Looking for your shows…"
        case .addingShows, .importingHistory: "Found \(Self.count(session.rows.count, "show"))"
        case .finished: session.addedCount == 0 ? "No shows added" : "\(Self.count(session.addedCount, "show")) added"
        case .failed: "Nothing imported"
        }
    }

    private var details: [String] {
        switch session.phase {
        case .idle, .reading:
            return []
        case .addingShows:
            return ["Adding \(session.doneCount) of \(session.rows.count)…"]
        case .importingHistory:
            return ["Importing listening history…"]
        case .failed(let message):
            return [message]
        case .finished:
            var lines: [String] = []
            if session.playedCount > 0 {
                lines.append("\(Self.count(session.playedCount, "episode")) marked played.")
            }
            if session.queuedCount > 0 {
                lines.append("\(Self.count(session.queuedCount, "episode")) to pick up, now in your Queue.")
            }
            if session.notFoundCount > 0 {
                lines.append("\(Self.count(session.notFoundCount, "show")) couldn't be found.")
            }
            return lines
        }
    }

    @ViewBuilder
    private var bottomButton: some View {
        Group {
            switch session.phase {
            case .finished:
                if session.queuedCount > 0 {
                    Button("Open Queue") { onFinish(.queue) }
                        .buttonStyle(.glassProminent)
                } else {
                    Button("Open Library") { onFinish(.library) }
                        .buttonStyle(.glassProminent)
                }
            case .failed:
                Button("Try Again", action: onRetry)
                    .buttonStyle(.glassProminent)
            default:
                Button("Continue in Background") { onFinish(.library) }
                    .buttonStyle(.glass)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, JimmyDesign.Spacing.lg)
        .padding(.bottom, JimmyDesign.Spacing.sm)
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value.formatted()) \(value == 1 ? noun : noun + "s")"
    }
}

private struct ImportShowRow: View {
    let row: LibraryImportSession.ShowRow
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 44

    var body: some View {
        HStack(spacing: JimmyDesign.Spacing.md) {
            BulletproofAsyncImage(url: row.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(uiColor: .secondarySystemFill)
            }
            .frame(width: min(side, 72), height: min(side, 72))
            .clipShape(RoundedRectangle(cornerRadius: min(side, 72) * 0.18, style: .continuous))
            .accessibilityHidden(true)

            Text(row.title)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch row.state {
            case .waiting:
                EmptyView()
            case .adding:
                ProgressView()
                    .accessibilityLabel("Adding")
            case .added:
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Added")
            case .notFound:
                Text("Not Found")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
