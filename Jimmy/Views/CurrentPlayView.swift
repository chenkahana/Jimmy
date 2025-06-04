import SwiftUI
import AVKit

struct CurrentPlayView: View {
    @ObservedObject private var queueViewModel = QueueViewModel.shared
    @ObservedObject private var audioPlayer = AudioPlayerService.shared
    @State private var isDownloading = false
    @State private var currentAudioRoute = ""
    @State private var showingEpisodeDetails = false
    
    var currentPlayingEpisode: Episode? {
        return audioPlayer.currentEpisode ?? queueViewModel.queue.first { $0.playbackPosition > 0 && !$0.played }
    }
    
    var currentOutputDevice: AudioOutputDevice {
        getCurrentAudioOutputDevice()
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if let currentEpisode = currentPlayingEpisode {
                    ModernNowPlayingView(
                        episode: currentEpisode,
                        podcast: getPodcast(for: currentEpisode),
                        isPlaying: audioPlayer.isPlaying,
                        currentTime: audioPlayer.playbackPosition,
                        duration: audioPlayer.duration,
                        isDownloading: $isDownloading,
                        showingEpisodeDetails: $showingEpisodeDetails,
                        currentOutputDevice: currentOutputDevice,
                        onPlayPause: {
                            if audioPlayer.currentEpisode?.id == currentEpisode.id {
                                audioPlayer.togglePlayPause()
                            } else {
                                audioPlayer.loadEpisode(currentEpisode)
                                audioPlayer.play()
                            }
                        },
                        onBackward: {
                            audioPlayer.seekBackward()
                        },
                        onForward: {
                            audioPlayer.seekForward()
                        },
                        onDownload: {
                            downloadEpisode(currentEpisode)
                        },
                        onSeek: { time in
                            audioPlayer.seek(to: time)
                        }
                    )
                } else {
                    EmptyPlayStateView()
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showingEpisodeDetails) {
                if let episode = currentPlayingEpisode,
                   let podcast = getPodcast(for: episode) {
                    EpisodeDetailsFullView(
                        episode: episode,
                        podcast: podcast,
                        isPresented: $showingEpisodeDetails
                    )
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            updateCurrentAudioRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            updateCurrentAudioRoute()
        }
    }
    
    private func getPodcast(for episode: Episode) -> Podcast? {
        return PodcastService.shared.loadPodcasts().first { $0.id == episode.podcastID }
    }
    
    private func downloadEpisode(_ episode: Episode) {
        isDownloading = true
        PodcastService.shared.downloadEpisode(episode) { url in
            DispatchQueue.main.async {
                isDownloading = false
            }
        }
    }
    
    private func updateCurrentAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        currentAudioRoute = session.currentRoute.outputs.first?.portName ?? "Unknown"
    }
    
    private func getCurrentAudioOutputDevice() -> AudioOutputDevice {
        let session = AVAudioSession.sharedInstance()
        guard let output = session.currentRoute.outputs.first else {
            return .speaker
        }
        
        switch output.portType {
        case .builtInSpeaker:
            return .speaker
        case .headphones:
            return .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return .bluetooth(name: output.portName)
        case .airPlay:
            return .airplay(name: output.portName)
        case .HDMI:
            return .hdmi(name: output.portName)
        case .lineOut:
            return .wired(name: output.portName)
        default:
            return .speaker
        }
    }
}

struct ModernNowPlayingView: View {
    let episode: Episode
    let podcast: Podcast?
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    @Binding var isDownloading: Bool
    @Binding var showingEpisodeDetails: Bool
    let currentOutputDevice: AudioOutputDevice
    let onPlayPause: () -> Void
    let onBackward: () -> Void
    let onForward: () -> Void
    let onDownload: () -> Void
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    
    var progressValue: Double {
        isDragging ? dragValue : (duration > 0 ? currentTime / duration : 0)
    }
    
    var outputIcon: String {
        switch currentOutputDevice {
        case .speaker:
            return "speaker.wave.3"
        case .headphones:
            return "headphones"
        case .bluetooth:
            return "airpods"
        case .airplay:
            return "airplayvideo"
        case .hdmi:
            return "tv"
        case .wired:
            return "headphones"
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top spacing
                Spacer()
                    .frame(height: 40)
                
                // Episode Artwork - Made larger and more prominent
                CachedAsyncImage(url: episode.artworkURL ?? podcast?.artworkURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.systemGray5),
                                    Color(.systemGray4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 72, weight: .thin))
                                .foregroundStyle(Color(.systemGray2))
                        )
                }
                .frame(width: min(geometry.size.width - 60, 280), height: min(geometry.size.width - 60, 280))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.2), radius: 25, x: 0, y: 12)
                
                Spacer()
                    .frame(height: 40)
                
                // Control Buttons Section - Matches your mockup layout
                VStack(spacing: 32) {
                    // Main control row with 5 buttons as shown in mockup
                    HStack(spacing: 0) {
                        // Download episode button (left)
                        Spacer()
                        ControlButton(
                            systemImage: isDownloading ? "arrow.down.circle.fill" : 
                                        PodcastService.shared.isEpisodeDownloaded(episode) ? "checkmark.circle.fill" : "arrow.down.circle",
                            size: .small,
                            color: PodcastService.shared.isEpisodeDownloaded(episode) ? .green : .primary,
                            action: onDownload,
                            isDisabled: isDownloading || PodcastService.shared.isEpisodeDownloaded(episode)
                        )
                        
                        Spacer()
                        
                        // Move backward button
                        ControlButton(
                            systemImage: "gobackward.15",
                            size: .small,
                            action: onBackward
                        )
                        
                        Spacer()
                        
                        // Play/Pause Button (Large center button) - Now uses accent color
                        ControlButton(
                            systemImage: isPlaying ? "pause.fill" : "play.fill",
                            size: .large,
                            color: .white,
                            backgroundColor: .accentColor,
                            action: onPlayPause
                        )
                        
                        Spacer()
                        
                        // Move forward button
                        ControlButton(
                            systemImage: "goforward.15",
                            size: .small,
                            action: onForward
                        )
                        
                        Spacer()
                        
                        // Choose output (airpods/speaker) button (right) - Native route picker
                        AVRoutePickerViewWrapper()
                            .frame(width: 48, height: 48)
                        
                        Spacer()
                    }
                    
                    // Progress Slider (below controls as in your design)
                    VStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { progressValue },
                                set: { newValue in
                                    dragValue = newValue
                                    if !isDragging {
                                        onSeek(newValue * duration)
                                    }
                                }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                isDragging = editing
                                if !editing {
                                    onSeek(dragValue * duration)
                                }
                            }
                        )
                        .accentColor(.accentColor)
                        .tint(.accentColor)
                        .frame(height: 6)
                        .onAppear {
                            // Make the slider thumb much smaller so it doesn't cover time text
                            UISlider.appearance().setThumbImage(createCircleImage(radius: 5, color: UIColor(Color.accentColor)), for: .normal)
                            UISlider.appearance().setThumbImage(createCircleImage(radius: 6, color: UIColor(Color.accentColor)), for: .highlighted)
                            
                            // Ensure the track uses accent color
                            UISlider.appearance().minimumTrackTintColor = UIColor(Color.accentColor)
                            UISlider.appearance().maximumTrackTintColor = UIColor(Color.accentColor.opacity(0.3))
                        }
                        
                        HStack {
                            Text(formatTime(isDragging ? dragValue * duration : currentTime))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            
                            Spacer()
                            
                            Text("-\(formatTime(duration - (isDragging ? dragValue * duration : currentTime)))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .padding(.horizontal, 20)
                
                Spacer()
                    .frame(height: 30)
                
                // Episode Details Section - Updated to show more details and allow expansion
                EpisodeDetailsSection(
                    episode: episode, 
                    podcast: podcast,
                    showingEpisodeDetails: $showingEpisodeDetails
                )
                
                Spacer()
                    .frame(height: 20)
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let time = max(0, time)
        let hours = Int(time) / 3600
        let minutes = Int(time) % 3600 / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func createCircleImage(radius: CGFloat, color: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(CGSize(width: radius * 2, height: radius * 2), false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2))
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

struct EpisodeDetailsSection: View {
    let episode: Episode
    let podcast: Podcast?
    @Binding var showingEpisodeDetails: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header without expand button
            HStack {
                Text("Episode Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            // Scrollable details container - Show full description
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .frame(minHeight: 200, maxHeight: 300)
                .overlay(
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 12) {
                            // Episode title - Allow more lines
                            HStack {
                                Text(episode.title)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            
                            // Podcast name
                            if let podcast = podcast {
                                HStack {
                                    Text("From: \(podcast.title)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                }
                            }
                            
                            // Episode description - Show full text
                            if let description = episode.description {
                                HStack {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                    }
                )
                .padding(.horizontal, 24)
        }
    }
}

// MARK: - Audio Output Selection

enum AudioOutputDevice: Hashable {
    case speaker
    case headphones
    case bluetooth(name: String)
    case airplay(name: String)
    case hdmi(name: String)
    case wired(name: String)
    
    var displayName: String {
        switch self {
        case .speaker:
            return "iPhone Speaker"
        case .headphones:
            return "Headphones"
        case .bluetooth(let name):
            return name
        case .airplay(let name):
            return name
        case .hdmi(let name):
            return name
        case .wired(let name):
            return name
        }
    }
    
    var icon: String {
        switch self {
        case .speaker:
            return "speaker.wave.3"
        case .headphones:
            return "headphones"
        case .bluetooth:
            return "airpods"
        case .airplay:
            return "airplayvideo"
        case .hdmi:
            return "tv"
        case .wired:
            return "headphones"
        }
    }
}

struct AudioOutputSelectionView: View {
    let currentDevice: AudioOutputDevice
    let onDeviceSelected: (AudioOutputDevice) -> Void
    @Environment(\.dismiss) private var dismiss
    
    // Mock available devices - In real implementation, you'd get these from AVAudioSession
    private let availableDevices: [AudioOutputDevice] = [
        .speaker,
        .headphones,
        .bluetooth(name: "Chen's AirPods Pro"),
        .airplay(name: "Living Room TV"),
        .airplay(name: "Bedroom"),
        .hdmi(name: "IL-DXRXMXRY44")
    ]
    
    var body: some View {
        NavigationView {
            devicesList
                .navigationTitle("Audio Output")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
    
    private var devicesList: some View {
        List {
            ForEach(availableDevices, id: \.self) { device in
                AudioOutputRow(
                    device: device,
                    isSelected: device == currentDevice,
                    onTap: {
                        onDeviceSelected(device)
                    }
                )
            }
        }
    }
}

struct AudioOutputRow: View {
    let device: AudioOutputDevice
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: device.icon)
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 30)
                
                Text(device.displayName)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .font(.headline)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Full Episode Details View

struct EpisodeDetailsFullView: View {
    let episode: Episode
    let podcast: Podcast
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            scrollContent
                .navigationTitle("Episode Details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            isPresented = false
                        }
                    }
                }
        }
    }
    
    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                episodeHeader
                episodeDescription
                Spacer(minLength: 100)
            }
            .padding(.vertical)
        }
    }
    
    private var episodeHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            episodeArtwork
            episodeInfo
            Spacer()
        }
        .padding(.horizontal)
    }
    
    private var episodeArtwork: some View {
        CachedAsyncImage(url: episode.artworkURL ?? podcast.artworkURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            artworkPlaceholder
        }
        .transition(.opacity.combined(with: .scale))
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .overlay(
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundColor(.secondary)
            )
    }
    
    private var episodeInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(episode.title)
                .font(.title2)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(podcast.title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let publishedDate = episode.publishedDate {
                Text(publishedDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var episodeDescription: some View {
        Group {
            if let description = episode.description {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Description")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                    
                    Text(description)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)
                }
            } else {
                EmptyView()
            }
        }
    }
}

struct ControlButton: View {
    let systemImage: String
    let size: ButtonSize
    var color: Color = .primary
    var backgroundColor: Color = Color(.systemGray5)
    let action: () -> Void
    var isDisabled: Bool = false
    
    enum ButtonSize {
        case small, large
        
        var dimension: CGFloat {
            switch self {
            case .small: return 48
            case .large: return 72
            }
        }
        
        var iconSize: Font {
            switch self {
            case .small: return .title3
            case .large: return .title
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(backgroundColor)
                .frame(width: size.dimension, height: size.dimension)
                .overlay(
                    Image(systemName: systemImage)
                        .font(size.iconSize)
                        .fontWeight(.medium)
                        .foregroundColor(color)
                )
                .shadow(
                    color: backgroundColor == .primary ? Color.black.opacity(0.25) : Color.black.opacity(0.08),
                    radius: backgroundColor == .primary ? 8 : 4,
                    x: 0,
                    y: backgroundColor == .primary ? 4 : 2
                )
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct EmptyPlayStateView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(Color(.systemGray3))
                
                VStack(spacing: 12) {
                    Text("No Episode Playing")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Choose an episode from your queue or library to start listening")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 48)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Native Audio Route Picker

struct AVRoutePickerViewWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        
        // Customize the appearance to match app design
        routePickerView.backgroundColor = UIColor.clear
        routePickerView.tintColor = UIColor(Color.primary)
        routePickerView.activeTintColor = UIColor(Color.accentColor)
        
        // Set the button style to match the control buttons
        routePickerView.prioritizesVideoDevices = false
        
        return routePickerView
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        // Update tint colors to match current theme
        uiView.tintColor = UIColor(Color.primary)
        uiView.activeTintColor = UIColor(Color.accentColor)
    }
}

#Preview {
    CurrentPlayView()
} 