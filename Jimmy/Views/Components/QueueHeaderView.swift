import SwiftUI

/// Header view for the Queue Tab redesign showing title and episode count/time info
struct QueueHeaderView: View {
    let episodeCount: Int
    let totalRemainingTime: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Up Next")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            HStack {
                Text("\(episodeCount) items • \(totalRemainingTime) left")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(.top, JimmyDesign.Spacing.lg)
        .padding(.bottom, JimmyDesign.Spacing.sm)
        .padding(.horizontal, JimmyDesign.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Queue header: \(episodeCount) episodes, \(totalRemainingTime) remaining")
    }
}

#Preview {
    VStack {
        QueueHeaderView(episodeCount: 5, totalRemainingTime: "2h 30m")
        Spacer()
    }
    .background(Color(.systemBackground))
} 