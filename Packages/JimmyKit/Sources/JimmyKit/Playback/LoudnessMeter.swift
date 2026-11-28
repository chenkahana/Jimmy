import Foundation

/// Measures integrated loudness (LUFS) the way ITU-R BS.1770 / EBU R128 define it: K-weighting,
/// 400 ms blocks with 75% overlap, an absolute gate at -70 LUFS and a relative gate 10 LU below
/// the ungated average. Feed it audio in any chunk size; read `integratedLUFS` when done.
///
/// Pure value-type math with no AVFoundation, so it runs the same in a unit test, in the offline
/// analyzer and on the Watch. It allocates while measuring, so it belongs on a background queue,
/// never in a real-time audio callback.
///
/// `samplePeak` is the highest absolute sample seen, not an oversampled true peak. The limiter
/// leaves 1 dB of headroom for that difference.
public nonisolated struct LoudnessMeter: Sendable {
    public let sampleRate: Double
    public let channelCount: Int

    /// Highest absolute sample value seen so far, linear (1.0 is full scale).
    public private(set) var samplePeak: Float = 0

    private var filters: [KWeighting]
    /// Sum of squared K-weighted samples in the 100 ms sub-block being filled, per channel.
    private var subBlockSums: [Double]
    private var subBlockFill = 0
    private let subBlockLength: Int
    /// Mean square per channel of the last four finished 100 ms sub-blocks (oldest first).
    private var recentSubBlocks: [[Double]] = []
    /// Power (summed over channels) of every finished 400 ms block.
    private var blockPowers: [Double] = []

    public init(sampleRate: Double, channelCount: Int) {
        precondition(sampleRate > 0 && channelCount > 0)
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.filters = Array(repeating: KWeighting(sampleRate: sampleRate), count: channelCount)
        self.subBlockSums = Array(repeating: 0, count: channelCount)
        self.subBlockLength = max(1, Int((sampleRate * 0.1).rounded()))
    }

    /// Adds audio. `channels` holds one array of samples per channel; all must be the same length.
    public mutating func process(channels: [[Float]]) {
        guard channels.count == channelCount, let frames = channels.first?.count else { return }
        for frame in 0..<frames {
            for channel in 0..<channelCount {
                let sample = channels[channel][frame]
                samplePeak = max(samplePeak, abs(sample))
                let weighted = filters[channel].process(Double(sample))
                subBlockSums[channel] += weighted * weighted
            }
            subBlockFill += 1
            if subBlockFill == subBlockLength { finishSubBlock() }
        }
    }

    private mutating func finishSubBlock() {
        let length = Double(subBlockLength)
        recentSubBlocks.append(subBlockSums.map { $0 / length })
        if recentSubBlocks.count > 4 { recentSubBlocks.removeFirst() }
        subBlockSums = Array(repeating: 0, count: channelCount)
        subBlockFill = 0
        guard recentSubBlocks.count == 4 else { return }
        var power = 0.0
        for channel in 0..<channelCount {
            power += recentSubBlocks.reduce(0.0) { $0 + $1[channel] } / 4
        }
        blockPowers.append(power)
    }

    /// Gated integrated loudness in LUFS, or `nil` when no 400 ms block was loud enough to count
    /// (silence, or less than 400 ms of audio).
    public var integratedLUFS: Double? {
        let absolute = blockPowers.filter { Self.lufs(forPower: $0) > -70 }
        guard !absolute.isEmpty else { return nil }
        let relativeThreshold = Self.lufs(forPower: absolute.reduce(0, +) / Double(absolute.count)) - 10
        let gated = absolute.filter { Self.lufs(forPower: $0) > relativeThreshold }
        guard !gated.isEmpty else { return nil }
        return Self.lufs(forPower: gated.reduce(0, +) / Double(gated.count))
    }

    static func lufs(forPower power: Double) -> Double {
        -0.691 + 10 * log10(max(power, 1e-20))
    }
}

/// The two-stage K-weighting filter from BS.1770: a high shelf that models the head, then a
/// 38 Hz high-pass. Coefficients are derived from the sample rate, so any rate works.
nonisolated struct KWeighting: Sendable {
    private nonisolated struct Biquad: Sendable {
        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        var z1 = 0.0, z2 = 0.0

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private var shelf = Biquad()
    private var highPass = Biquad()

    init(sampleRate: Double) {
        let shelfFrequency = 1681.974450955533
        let shelfGainDB = 3.999843853973347
        let shelfQ = 0.7071752369554196
        var k = tan(Double.pi * shelfFrequency / sampleRate)
        let vh = pow(10, shelfGainDB / 20)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / shelfQ + k * k
        shelf.b0 = (vh + vb * k / shelfQ + k * k) / a0
        shelf.b1 = 2 * (k * k - vh) / a0
        shelf.b2 = (vh - vb * k / shelfQ + k * k) / a0
        shelf.a1 = 2 * (k * k - 1) / a0
        shelf.a2 = (1 - k / shelfQ + k * k) / a0

        let highPassFrequency = 38.13547087602444
        let highPassQ = 0.5003270373238773
        k = tan(Double.pi * highPassFrequency / sampleRate)
        a0 = 1 + k / highPassQ + k * k
        highPass.b0 = 1
        highPass.b1 = -2
        highPass.b2 = 1
        highPass.a1 = 2 * (k * k - 1) / a0
        highPass.a2 = (1 - k / highPassQ + k * k) / a0
    }

    mutating func process(_ x: Double) -> Double {
        highPass.process(shelf.process(x))
    }
}
