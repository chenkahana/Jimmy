import XCTest
@testable import Jimmy

@MainActor
final class FeatureFlagServiceTests: XCTestCase {
    var sut: FeatureFlagService!

    override func setUp() async throws {
        try await super.setUp()
        sut = FeatureFlagService.shared
        sut.resetToDefaults()
    }

    override func tearDown() async throws {
        sut?.resetToDefaults()
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Feature Flag Tests

    func testFeatureFlagInitialState() {
        let isEnabled = sut.isEnabled(.liquidGlassTabBar)
        XCTAssertTrue(isEnabled, "Development builds should enable design flags by default")
    }

    func testToggleFeatureFlag() {
        let initialState = sut.isEnabled(.liquidGlassTabBar)

        sut.toggle(.liquidGlassTabBar)

        let newState = sut.isEnabled(.liquidGlassTabBar)
        XCTAssertNotEqual(initialState, newState, "Feature flag should toggle")
    }

    func testToggleFeatureFlagTwice() {
        let initialState = sut.isEnabled(.liquidGlassTabBar)

        sut.toggle(.liquidGlassTabBar)
        sut.toggle(.liquidGlassTabBar)

        let finalState = sut.isEnabled(.liquidGlassTabBar)
        XCTAssertEqual(initialState, finalState, "Feature flag should return to initial state after two toggles")
    }
}
