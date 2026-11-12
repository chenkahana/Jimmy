import XCTest
@testable import Jimmy

/// When the first-run import shows, and `-resetOnboarding` bringing it back.
@MainActor
final class OnboardingTests: XCTestCase {
    func testShowsOnFirstLaunchWithEmptyLibrary() {
        XCTAssertTrue(Onboarding.shouldPresent(hasCompleted: false, podcastCount: 0, arguments: []))
    }

    func testHiddenOnceCompletedOrForExistingLibrary() {
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: true, podcastCount: 0, arguments: []))
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: false, podcastCount: 12, arguments: []))
    }

    func testLaunchArguments() {
        XCTAssertTrue(Onboarding.shouldPresent(hasCompleted: true, podcastCount: 12, arguments: ["-resetOnboarding"]))
        let skipAndReset = ["-skipOnboarding", "-resetOnboarding"]
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: false, podcastCount: 0, arguments: skipAndReset))
        XCTAssertFalse(Onboarding.shouldPresent(hasCompleted: false, podcastCount: 0, arguments: ["-demoLibrary"]))
        let demoAndReset = ["-demoLibrary", "-resetOnboarding"]
        XCTAssertTrue(Onboarding.shouldPresent(hasCompleted: false, podcastCount: 0, arguments: demoAndReset))
    }

    func testExistingLibraryIsMarkedCompletedAndResetClearsIt() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "OnboardingTests-\(UUID().uuidString)"))
        let onboarding = Onboarding(defaults: defaults)

        onboarding.presentIfNeeded(podcastCount: 3, arguments: [])
        XCTAssertFalse(onboarding.isPresented)
        XCTAssertTrue(defaults.bool(forKey: Onboarding.completedKey))

        onboarding.presentIfNeeded(podcastCount: 3, arguments: ["-resetOnboarding"])
        XCTAssertTrue(onboarding.isPresented)

        onboarding.finish()
        XCTAssertFalse(onboarding.isPresented)
        XCTAssertTrue(defaults.bool(forKey: Onboarding.completedKey))
    }

    func testSharedFilesThatAreImports() {
        XCTAssertTrue(Onboarding.isImportFile(URL(fileURLWithPath: "/tmp/overcast.opml")))
        XCTAssertTrue(Onboarding.isImportFile(URL(fileURLWithPath: "/tmp/YourLibrary.JSON")))
        XCTAssertFalse(Onboarding.isImportFile(URL(fileURLWithPath: "/tmp/episode.mp3")))
    }
}
