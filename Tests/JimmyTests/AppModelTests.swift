import XCTest
@testable import Jimmy

@MainActor
final class AppModelTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testOpensSuccessfullyOnAFreshTemporaryPath() {
        let path = makeTempDirectory().appendingPathComponent("jimmy.db").path

        let model = AppModel(databasePath: path)

        guard case .ready = model.launchState else {
            XCTFail("Expected AppModel to open successfully at a fresh temporary path")
            return
        }
    }

    func testAnUnopenablePathYieldsAFailedLaunchStateInsteadOfCrashing() {
        // A directory can't be opened as a SQLite database file, so this exercises the open
        // failure path without needing to corrupt an actual database file.
        let directoryAsPath = makeTempDirectory().path

        let model = AppModel(databasePath: directoryAsPath)

        guard case .failed(let failure) = model.launchState else {
            XCTFail("Expected AppModel to report a failed launch state for an unopenable path")
            return
        }
        XCTAssertFalse(failure.message.isEmpty)
    }
}
