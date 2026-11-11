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

    // MARK: - Launch database path selection

    func testDemoLibraryArgumentNeverSelectsTheRealDatabasePath() {
        let path = AppModel.launchDatabasePath(arguments: ["Jimmy", "-demoLibrary"], isRunningUnitTests: false)

        XCTAssertNotEqual(path, AppModel.defaultDatabasePath())
        XCTAssertTrue(
            path.hasPrefix(FileManager.default.temporaryDirectory.path),
            "Expected the demo library path to live under the temporary directory, got \(path)"
        )
    }

    func testDemoLibraryArgumentWinsOverUnitTestMode() {
        // `-demoLibrary` still shouldn't collide with the regular unit-test temp path, which a
        // demo-library launch has no reason to share.
        let path = AppModel.launchDatabasePath(arguments: ["Jimmy", "-demoLibrary"], isRunningUnitTests: true)

        XCTAssertNotEqual(path, AppModel.defaultDatabasePath())
        XCTAssertTrue(path.contains("AppModel-Demo-"))
    }

    func testWithoutTheDemoLibraryArgumentUnitTestsStillGetATemporaryPath() {
        let path = AppModel.launchDatabasePath(arguments: ["Jimmy"], isRunningUnitTests: true)

        XCTAssertNotEqual(path, AppModel.defaultDatabasePath())
    }

    func testWithoutTheDemoLibraryArgumentOrUnitTestsTheRealDatabasePathIsUsed() {
        let path = AppModel.launchDatabasePath(arguments: ["Jimmy"], isRunningUnitTests: false)

        XCTAssertEqual(path, AppModel.defaultDatabasePath())
    }
}
