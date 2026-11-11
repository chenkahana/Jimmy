import SwiftUI
import AVKit

/// SwiftUI wrapper for AVRoutePickerView with dynamic audio route icon overlay
struct AVRoutePickerViewWrapper: UIViewRepresentable {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.backgroundColor = UIColor.clear
        routePickerView.tintColor = UIColor.label
        return routePickerView
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // No updates needed
    }
}

/// Enhanced route picker with dynamic icon overlay
struct DynamicRoutePickerView: View {
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    
    var body: some View {
        ZStack {
            // Invisible route picker for functionality
            AVRoutePickerViewWrapper()
                .opacity(0.01) // Nearly invisible but still touchable
            
            // Dynamic icon overlay
            Button(action: {
                // This will be handled by the invisible route picker
            }) {
                Image(systemName: audioPlayer.currentAudioRoute.iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .liquidGlassBackground(
                        cornerRadius: 22,
                        shadowOpacity: 0.1,
                        material: .ultraThinMaterial
                    )
            }
            .disabled(true) // Let the route picker handle touches
        }
    }
} 