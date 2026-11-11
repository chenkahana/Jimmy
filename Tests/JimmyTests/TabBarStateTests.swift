import XCTest
@testable import Jimmy

@MainActor
final class TabBarStateTests: XCTestCase {
    
    var stateManager: TabBarStateManagerV3!
    
    override func setUp() async throws {
        stateManager = TabBarStateManagerV3()
    }
    
    override func tearDown() async throws {
        stateManager = nil
    }
    
    // MARK: - State Transition Tests
    
    func testInitialState() {
        XCTAssertEqual(stateManager.currentState, .full, "Initial state should be full")
        XCTAssertFalse(stateManager.isSearchActive, "Search should not be active initially")
        XCTAssertEqual(stateManager.selectedTab, 0, "Selected tab should be 0 initially")
    }
    
    func testSearchActivationTransition() async {
        // When search activates
        stateManager.handleSearchActivation()
        
        // Wait for debounce
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Then state should be minimized
        XCTAssertTrue(stateManager.isSearchActive, "Search should be active")
        XCTAssertEqual(stateManager.currentState, .minimized, "State should be minimized")
    }
    
    func testSearchDismissalTransition() async {
        // Given search is active
        stateManager.handleSearchActivation()
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // When search is dismissed
        stateManager.handleSearchDismissal()
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then state should be full
        XCTAssertFalse(stateManager.isSearchActive, "Search should not be active")
        XCTAssertEqual(stateManager.currentState, .full, "State should be full")
    }
    
    func testRapidStateChanges() async {
        // Rapidly toggle search state
        for _ in 0..<5 {
            stateManager.handleSearchActivation()
            stateManager.handleSearchDismissal()
        }
        
        // Wait for all debounces to complete
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Should end in dismissed state
        XCTAssertFalse(stateManager.isSearchActive, "Search should not be active after rapid changes")
        XCTAssertEqual(stateManager.currentState, .full, "State should be full after rapid changes")
    }
    
    // MARK: - Computed Property Tests
    
    func testTabBarHeightInFullState() {
        stateManager.updateState(.full, animated: false)
        XCTAssertEqual(stateManager.tabBarHeight, 64, "Tab bar height should be 64pt in full state")
    }
    
    func testTabBarHeightInMinimizedState() {
        stateManager.updateState(.minimized, animated: false)
        XCTAssertEqual(stateManager.tabBarHeight, 32, "Tab bar height should be 32pt in minimized state")
    }
    
    func testTabBarHeightWithAccessory() {
        stateManager.updateState(.withAccessory(height: 50), animated: false)
        XCTAssertEqual(stateManager.tabBarHeight, 114, "Tab bar height should be 64 + 50 = 114pt with accessory")
    }
    
    func testShouldShowLabelsInFullState() {
        stateManager.updateState(.full, animated: false)
        XCTAssertTrue(stateManager.shouldShowLabels, "Labels should show in full state")
    }
    
    func testShouldShowLabelsInMinimizedState() {
        stateManager.updateState(.minimized, animated: false)
        XCTAssertFalse(stateManager.shouldShowLabels, "Labels should not show in minimized state")
    }
    
    func testShouldShowSelectionIndicatorInFullState() {
        stateManager.updateState(.full, animated: false)
        XCTAssertTrue(stateManager.shouldShowSelectionIndicator, "Selection indicator should show in full state")
    }
    
    func testShouldShowSelectionIndicatorInMinimizedState() {
        stateManager.updateState(.minimized, animated: false)
        XCTAssertFalse(stateManager.shouldShowSelectionIndicator, "Selection indicator should not show in minimized state")
    }
    
    // MARK: - Tab Selection Tests
    
    func testTabSelection() {
        stateManager.selectedTab = 2
        XCTAssertEqual(stateManager.selectedTab, 2, "Selected tab should update")
    }
    
    func testMultipleTabSelections() {
        for i in 0..<5 {
            stateManager.selectedTab = i
            XCTAssertEqual(stateManager.selectedTab, i, "Selected tab should be \(i)")
        }
    }
}
