import SwiftUI

struct QueueStatsHeader: View {
    let episodeCount: Int
    let totalRemainingTime: String

    var body: some View {
        HStack(spacing: 16) {
            Label {
                Text("\(episodeCount)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundColor(.primary)
                +
                Text(" \(episodeCount == 1 ? "episode" : "episodes")")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "list.number")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            Divider()
                .frame(height: 24)

            Label {
                Text(totalRemainingTime)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.secondary)
            } icon: {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
