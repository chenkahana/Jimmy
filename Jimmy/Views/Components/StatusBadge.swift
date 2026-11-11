import SwiftUI

struct StatusBadge: View {
    let episode: Episode
    
    var body: some View {
        HStack(spacing: 2) {
            if episode.status.contains(.playing) {
                playingBadge
            } else if episode.status.contains(.queued) {
                queuedBadge
            } else if episode.status.contains(.played) {
                playedBadge
            }
        }

    }
    
    private var playingBadge: some View {
        Image(systemName: "waveform")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .symbolEffect(.pulse.byLayer, options: .repeating)
            .frame(width: 16, height: 16)
            .background(
                Circle()
                    .fill(.regularMaterial)
                    .overlay(
                        Circle()
                            .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
    }
    
    private var queuedBadge: some View {
        Image(systemName: "list.bullet")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: 16, height: 16)
            .background(
                Circle()
                    .fill(.regularMaterial)
                    .overlay(
                        Circle()
                            .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
    }
    
    private var playedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: 16, height: 16)
            .background(
                Circle()
                    .fill(.regularMaterial)
                    .overlay(
                        Circle()
                            .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
    }
}

// MARK: - Helper function for views
extension View {
    func statusBadge(for episode: Episode) -> some View {
        self.overlay(
            StatusBadge(episode: episode)
                .offset(x: -4, y: 4), // Subtle offset for refined look
            alignment: .topTrailing
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        StatusBadge(episode: Episode(title: "Playing Episode", status: .playing))
        StatusBadge(episode: Episode(title: "Queued Episode", status: .queued))
        StatusBadge(episode: Episode(title: "Played Episode", status: .played))
        StatusBadge(episode: Episode(title: "Queued & Played Episode", status: [.queued, .played]))
    }
    .padding()
} 