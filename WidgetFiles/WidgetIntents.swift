import AppIntents
import Foundation

// Play/Pause Intent
struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    static var description = IntentDescription("Toggle play/pause for the current episode.")
    
    func perform() async throws -> some IntentResult {
        let audioService = AudioPlayerService.shared
        audioService.togglePlayPause()
        return .result()
    }
}

// Seek Backward Intent
struct SeekBackwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Seek Backward"
    static var description = IntentDescription("Seek backward 15 seconds.")
    
    func perform() async throws -> some IntentResult {
        let audioService = AudioPlayerService.shared
        audioService.seekBackward()
        return .result()
    }
}

// Seek Forward Intent
struct SeekForwardIntent: AppIntent {
    static var title: LocalizedStringResource = "Seek Forward"
    static var description = IntentDescription("Seek forward 15 seconds.")
    
    func perform() async throws -> some IntentResult {
        let audioService = AudioPlayerService.shared
        audioService.seekForward()
        return .result()
    }
} 