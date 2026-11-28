import Foundation
import AVFoundation

#if canImport(MediaToolbox)
import AudioToolbox
import MediaToolbox
import Synchronization

/// Carries the volume boost settings to the audio thread and owns the DSP that runs there.
///
/// The main thread changes the settings through atomics; the audio thread reads them in
/// `process`. The processor and follower are created in `prepare`, which the system always calls
/// before the first `process`, so no allocation happens on the audio thread.
nonisolated final class LoudnessTapState: @unchecked Sendable {
    private enum Layout {
        case planar(channels: Int)
        case interleaved(channels: Int)
    }

    private let targetLUFSBits: Atomic<UInt64>
    private let compressor: Atomic<Bool>
    private var processor: LoudnessProcessor?
    private var follower: LoudnessFollower?
    private var layout: Layout?

    init(boost: VolumeBoost) {
        targetLUFSBits = Atomic((boost.targetLUFS ?? -16).bitPattern)
        compressor = Atomic(boost.usesCompressor)
    }

    /// Safe to call from any thread while audio is playing.
    func update(boost: VolumeBoost) {
        targetLUFSBits.store((boost.targetLUFS ?? -16).bitPattern, ordering: .relaxed)
        compressor.store(boost.usesCompressor, ordering: .relaxed)
    }

    func prepare(sampleRate: Double, format: AudioStreamBasicDescription) {
        let channels = Int(format.mChannelsPerFrame)
        let isFloat32 = format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        guard isFloat32, (1...2).contains(channels), sampleRate > 0 else {
            // A format the DSP doesn't handle: leave the audio untouched rather than risk garbage.
            layout = nil
            return
        }
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        layout = planar ? .planar(channels: channels) : .interleaved(channels: channels)
        processor = LoudnessProcessor(sampleRate: sampleRate, gainTimeConstant: 1.0)
        follower = LoudnessFollower(sampleRate: sampleRate, channelCount: channels)
    }

    func unprepare() {
        layout = nil
        processor = nil
        follower = nil
    }

    func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard let processor, let follower, let layout, frameCount > 0 else { return }
        let target = Double(bitPattern: targetLUFSBits.load(ordering: .relaxed))
        processor.compressorEnabled = compressor.load(ordering: .relaxed)

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        let left: UnsafeMutablePointer<Float>
        var right: UnsafeMutablePointer<Float>?
        let stride: Int
        switch layout {
        case .planar(let channels):
            guard buffers.count >= channels, let first = buffers[0].mData else { return }
            left = first.assumingMemoryBound(to: Float.self)
            if channels == 2 {
                guard let second = buffers[1].mData else { return }
                right = second.assumingMemoryBound(to: Float.self)
            }
            stride = 1
        case .interleaved(let channels):
            guard buffers.count >= 1, let first = buffers[0].mData else { return }
            left = first.assumingMemoryBound(to: Float.self)
            if channels == 2 { right = left + 1 }
            stride = channels
        }

        // Measure the untouched signal first, then ease the gain toward what the estimate asks.
        follower.process(
            left: UnsafePointer(left),
            right: right.map { UnsafePointer($0) },
            frameCount: frameCount,
            leftStride: stride,
            rightStride: stride
        )
        if let estimate = follower.estimatedLUFS {
            let gain = min(VolumeBoost.maxGainDB, max(-VolumeBoost.maxGainDB, target - estimate))
            processor.targetGainDB = gain
        }
        processor.process(left: left, right: right, frameCount: frameCount, leftStride: stride, rightStride: stride)
    }
}

// MARK: - MTAudioProcessingTap plumbing

private nonisolated func tapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ storageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    storageOut.pointee = clientInfo
}

private nonisolated func tapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<LoudnessTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private nonisolated func tapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ format: UnsafePointer<AudioStreamBasicDescription>
) {
    let state = Unmanaged<LoudnessTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    state.prepare(sampleRate: format.pointee.mSampleRate, format: format.pointee)
}

private nonisolated func tapUnprepare(_ tap: MTAudioProcessingTap) {
    Unmanaged<LoudnessTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().unprepare()
}

private nonisolated func tapProcess(
    _ tap: MTAudioProcessingTap,
    _ frames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferList: UnsafeMutablePointer<AudioBufferList>,
    _ framesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut)
    guard status == noErr else { return }
    let state = Unmanaged<LoudnessTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    state.process(bufferList, frameCount: framesOut.pointee)
}

enum LoudnessTap {
    /// An audio mix that runs `state`'s processing on `track`, or `nil` when the tap can't be made.
    /// The mix keeps `state` alive for as long as the tap exists.
    static func audioMix(for track: AVAssetTrack, state: LoudnessTapState) -> AVAudioMix? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(state).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, let tap else {
            // The tap was not created, so finalize will never balance the retain above.
            Unmanaged.passUnretained(state).release()
            return nil
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }
}
#endif
