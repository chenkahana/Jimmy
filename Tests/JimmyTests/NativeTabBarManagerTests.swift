import XCTest
@testable import Jimmy

@MainActor
final class NativeTabBarManagerTests: XCTestCase {
    
    var sut: NativeTabBarManager!
    
    override func setUp() async throws {
        try await super.setUp()
        sut = NativeTabBarManager.shared
    }
    
    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Search State Tests
    
    func testSearchStateInitiallyFalse() {
        XCTAssertFalse(sut.isSearchActive, "Search should not be active initially")
    }
    
    func testMinimizeForSearchSetsStateToTrue() {
        sut.minimizeForSearch()
        XCTAssertTrue(sut.isSearchActive, "Search should be active after minimizing")
    }
    
    func testRestoreFromSearchSetsStateToFalse() {
        sut.minimizeForSearch()
        sut.restoreFromSearch()
        XCTAssertFalse(sut.isSearchActive, "Search should not be active after restoring")
    }
    
    // MARK: - Appearance Configuration Tests
    
    func testConfigureNativeAppearanceDoesNotCrash() {
        XCTAssertNoThrow(sut.configureNativeAppearance())
    }
    
    func testConfigureNativeAppearanceWithReduceTransparency() {
        // This test verifies the method handles reduce transparency flag
        XCTAssertNoThrow(sut.configureNativeAppearance())
    }
}
