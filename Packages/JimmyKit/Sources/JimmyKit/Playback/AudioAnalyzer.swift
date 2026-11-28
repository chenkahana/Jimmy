import Foundation
import AVFoundation

/// The result of `AudioAnalyzer.analyze`, before it is tied to an episode.
public nonisolated struct AudioAnalysisResult: Sendable, Hashable {
    public var integratedLUFS: Double?
    public var samplePeak: Double
    public var silenceRanges: [SilenceRange]
}

public nonisolated enum AudioAnalyzerError: Error, Sendable {
    case noAudioTrack
    case cannotRead
    case unsupportedFormat
}

#if !os(watchOS)
/// Decodes a local audio file once and runs the loudness meter and the silence detector over it.
/// Slow on long episodes (it decodes the whole file), so call it from a background task, never
/// the main actor. Cancelling the calling task stops it between buffers.
public nonisolated enum AudioAnalyzer {
    public static func analyze(fileURL: URL) async throws -> AudioAnalysisResult {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioAnalyzerError.noAudioTrack
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              basic.mSampleRate > 0
        else { throw AudioAnalyzerError.unsupportedFormat }
        let channels = min(2, max(1, Int(basic.mChannelsPerFrame)))
        let sampleRate = basic.mSampleRate

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ])
        guard reader.canAdd(output) else { throw AudioAnalyzerError.cannotRead }
        reader.add(output)
        guard reader.startReading() else { throw AudioAnalyzerError.cannotRead }

        var meter = LoudnessMeter(sampleRate: sampleRate, channelCount: channels)
        var silence = SilenceDetector(sampleRate: sampleRate)
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw AudioAnalyzerError.cannotRead }
            let (planar, loudest) = split(samples, channels: channels)
            meter.process(channels: planar)
            silence.process(loudest)
        }
        guard reader.status == .completed else { throw AudioAnalyzerError.cannotRead }
        return AudioAnalysisResult(
            integratedLUFS: meter.integratedLUFS,
            samplePeak: Double(meter.samplePeak),
            silenceRanges: silence.finish()
        )
    }

    /// Splits interleaved samples into one array per channel, plus one value per frame: the louder
    /// channel, which is what decides whether a frame is silent.
    static func split(_ interleaved: [Float], channels: Int) -> ([[Float]], [Float]) {
        let frames = interleaved.count / channels
        var planar = [[Float]](repeating: [Float](repeating: 0, count: frames), count: channels)
        var loudest = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channels {
                let sample = interleaved[frame * channels + channel]
                planar[channel][frame] = sample
                peak = max(peak, abs(sample))
            }
            loudest[frame] = peak
        }
        return (planar, loudest)
    }
}
#endif
