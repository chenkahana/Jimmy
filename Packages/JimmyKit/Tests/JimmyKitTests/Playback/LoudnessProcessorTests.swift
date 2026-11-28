import Foundation
import Testing
@testable import JimmyKit

struct LoudnessProcessorTests {
    private let sampleRate = 48_000.0
    private let ceiling = Float(pow(10, LoudnessProcessor.ceilingDBFS / 20))

    private func run(
        _ processor: LoudnessProcessor,
        _ input: [Float]
    ) -> [Float] {
        var buffer = input
        buffer.withUnsafeMutableBufferPointer { pointer in
            processor.process(left: pointer.baseAddress!, right: nil, frameCount: pointer.count)
        }
        return buffer
    }

    @Test func limiterHoldsASixDecibelOverloadedSineUnderTheCeiling() {
        let processor = LoudnessProcessor(sampleRate: sampleRate)
        let output = run(processor, LoudnessTestSignals.sine(amplitude: 2.0, frequency: 440, seconds: 1))
        #expect(LoudnessTestSignals.peak(output[...]) <= ceiling + 0.0001)
    }

    @Test func limiterHoldsAFullScaleSquareWaveWithMaximumGainUnderTheCeiling() {
        let processor = LoudnessProcessor(sampleRate: sampleRate, gainDB: 12)
        let output = run(processor, LoudnessTestSignals.square(amplitude: 1, seconds: 1))
        #expect(LoudnessTestSignals.peak(output[...]) <= ceiling + 0.0001)
    }

    @Test func limiterHoldsBothChannelsOfAPlanarStereoBuffer() {
        let processor = LoudnessProcessor(sampleRate: sampleRate, gainDB: 12)
        var left = LoudnessTestSignals.sine(amplitude: 0.9, frequency: 300, seconds: 1)
        var right = LoudnessTestSignals.sine(amplitude: 0.5, frequency: 500, seconds: 1)
        let count = left.count
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                processor.process(left: l.baseAddress!, right: r.baseAddress!, frameCount: count)
            }
        }
        #expect(LoudnessTestSignals.peak(left[...]) <= ceiling + 0.0001)
        #expect(LoudnessTestSignals.peak(right[...]) <= ceiling + 0.0001)
    }

    @Test func interleavedStereoMatchesPlanar() {
        let l = LoudnessTestSignals.sine(amplitude: 0.4, frequency: 300, seconds: 0.5)
        let r = LoudnessTestSignals.sine(amplitude: 0.2, frequency: 500, seconds: 0.5)
        let count = l.count

        var planarLeft = l
        var planarRight = r
        let planar = LoudnessProcessor(sampleRate: sampleRate, gainDB: 6, compressorEnabled: true)
        planarLeft.withUnsafeMutableBufferPointer { lp in
            planarRight.withUnsafeMutableBufferPointer { rp in
                planar.process(left: lp.baseAddress!, right: rp.baseAddress!, frameCount: count)
            }
        }

        var interleaved = [Float](repeating: 0, count: count * 2)
        for index in 0..<count {
            interleaved[index * 2] = l[index]
            interleaved[index * 2 + 1] = r[index]
        }
        let other = LoudnessProcessor(sampleRate: sampleRate, gainDB: 6, compressorEnabled: true)
        interleaved.withUnsafeMutableBufferPointer { pointer in
            let base = pointer.baseAddress!
            other.process(left: base, right: base + 1, frameCount: count, leftStride: 2, rightStride: 2)
        }

        for index in stride(from: 0, to: count, by: 97) {
            #expect(abs(interleaved[index * 2] - planarLeft[index]) < 0.00001)
            #expect(abs(interleaved[index * 2 + 1] - planarRight[index]) < 0.00001)
        }
    }

    @Test func atUnityGainAQuietSignalPassesThroughDelayedByTheLookAhead() {
        let processor = LoudnessProcessor(sampleRate: sampleRate)
        let input = LoudnessTestSignals.sine(amplitude: 0.1, frequency: 440, seconds: 0.5)
        let output = run(processor, input)
        let latency = processor.latencyFrames
        for index in 2_000..<4_000 {
            #expect(abs(output[index] - input[index - latency]) < 0.0001)
        }
    }

    @Test func gainRaisesTheLevelByTheRequestedDecibels() {
        let processor = LoudnessProcessor(sampleRate: sampleRate, gainDB: 6)
        let output = run(processor, LoudnessTestSignals.sine(amplitude: 0.1, frequency: 440, seconds: 0.5))
        let peak = LoudnessTestSignals.peak(output[10_000...])
        #expect(abs(peak - 0.1 * 1.9953) < 0.002)
    }

    @Test func targetGainIsClamped() {
        let processor = LoudnessProcessor(sampleRate: sampleRate)
        processor.targetGainDB = 40
        #expect(processor.targetGainDB == VolumeBoost.maxGainDB)
        processor.targetGainDB = -40
        #expect(processor.targetGainDB == -VolumeBoost.maxGainDB)
    }

    @Test func compressorAppliesTwoToOneAboveTheThreshold() {
        // A square wave at -4 dBFS sits 20 dB over the -24 dBFS threshold, so 2:1 takes 10 dB off.
        let processor = LoudnessProcessor(sampleRate: sampleRate, compressorEnabled: true)
        let output = run(processor, LoudnessTestSignals.square(amplitude: 0.631, seconds: 2))
        let level = LoudnessTestSignals.peak(output[(output.count - 4_800)...])
        #expect(abs(level - 0.631 * 0.3162) < 0.01)
    }

    @Test func compressorLeavesQuietSignalsAlone() {
        let processor = LoudnessProcessor(sampleRate: sampleRate, compressorEnabled: true)
        let output = run(processor, LoudnessTestSignals.square(amplitude: 0.02, seconds: 1))
        let level = LoudnessTestSignals.peak(output[(output.count - 4_800)...])
        #expect(abs(level - 0.02) < 0.0005)
    }

    @Test func levelingAQuietEpisodeLandsWithinOneLUOfTheTarget() throws {
        var before = LoudnessMeter(sampleRate: sampleRate, channelCount: 1)
        let input = LoudnessTestSignals.sine(amplitude: 0.08, seconds: 8)
        before.process(channels: [input])
        let measured = try #require(before.integratedLUFS)

        let gain = VolumeBoost.normal.gainDB(measuredLUFS: measured)
        let output = run(LoudnessProcessor(sampleRate: sampleRate, gainDB: gain), input)

        var after = LoudnessMeter(sampleRate: sampleRate, channelCount: 1)
        after.process(channels: [output])
        let leveled = try #require(after.integratedLUFS)
        #expect(abs(leveled - -16) < 1)
    }

    @Test func levelingALoudEpisodeBringsItDown() throws {
        var before = LoudnessMeter(sampleRate: sampleRate, channelCount: 1)
        let input = LoudnessTestSignals.sine(amplitude: 0.7, seconds: 8)
        before.process(channels: [input])
        let measured = try #require(before.integratedLUFS)
        #expect(VolumeBoost.normal.gainDB(measuredLUFS: measured) < 0)
    }
}
