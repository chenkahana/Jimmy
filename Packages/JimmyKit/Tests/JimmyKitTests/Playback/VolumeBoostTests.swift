import Testing
@testable import JimmyKit

struct VolumeBoostTests {
    @Test func targets() {
        #expect(VolumeBoost.off.targetLUFS == nil)
        #expect(VolumeBoost.normal.targetLUFS == -16)
        #expect(VolumeBoost.high.targetLUFS == -14)
    }

    @Test func gainIsTargetMinusMeasured() {
        #expect(VolumeBoost.normal.gainDB(measuredLUFS: -22) == 6)
        #expect(VolumeBoost.normal.gainDB(measuredLUFS: -12) == -4)
        #expect(VolumeBoost.high.gainDB(measuredLUFS: -22) == 8)
    }

    @Test func gainIsClamped() {
        #expect(VolumeBoost.normal.gainDB(measuredLUFS: -50) == 12)
        #expect(VolumeBoost.normal.gainDB(measuredLUFS: 0) == -12)
    }

    @Test func offOrUnmeasuredMeansNoGain() {
        #expect(VolumeBoost.off.gainDB(measuredLUFS: -30) == 0)
        #expect(VolumeBoost.normal.gainDB(measuredLUFS: nil) == 0)
        #expect(VolumeBoost.normal.gainDB(measuredLUFS: -.infinity) == 0)
    }
}
