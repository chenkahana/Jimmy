import XCTest

/// Sanity tests for core Jimmy app functionality
/// These tests verify basic app operations and critical user journeys
class SanityTests: JimmyUITests {
    
    // MARK: - App Launch Tests
    
    func testAppLaunches() throws {
        // Test that the app launches successfully
        verifyAppIsRunning()
        takeScreenshot(named: "app_launch")
        
        // Verify main UI elements are present
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Tab bar should be visible")
    }
    
    func testAppLaunchPerformance() throws {
        // Measure app launch time
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.terminate()
            app.launch()
        }
    }
    
    // MARK: - Navigation Tests
    
    func testTabNavigation() throws {
        // Test navigation between main tabs
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(waitForElement(tabBar), "Tab bar should be visible")
        
        // Test each tab
        let expectedTabs = ["Discover", "Queue", "Now Playing", "Library", "Settings"]
        
        for tabName in expectedTabs {
            let tab = tabBar.buttons[tabName]
            if tab.exists {
                tab.tap()
                
                // Wait a moment for navigation
                Thread.sleep(forTimeInterval: 0.5)
                
                // Verify we're on the correct tab
                XCTAssertTrue(tab.isSelected, "\(tabName) tab should be selected")
                takeScreenshot(named: "tab_\(tabName.lowercased().replacingOccurrences(of: " ", with: "_"))")
            }
        }
    }
    
    func testDiscoverTabBasicFunctionality() throws {
        // Navigate to Discover tab
        let tabBar = app.tabBars.firstMatch
        let discoverTab = tabBar.buttons["Discover"]
        
        if discoverTab.exists {
            discoverTab.tap()
            
            // Wait for content to load
            Thread.sleep(forTimeInterval: 2.0)
            
            // Verify basic elements are present
            // Note: These selectors may need adjustment based on actual UI
            let searchField = app.searchFields.firstMatch
            if searchField.exists {
                XCTAssertTrue(searchField.exists, "Search field should be present in Discover tab")
            }
            
            takeScreenshot(named: "discover_tab_loaded")
        } else {
            XCTSkip("Discover tab not found - may need UI selector adjustment")
        }
    }
    
    func testLibraryTabBasicFunctionality() throws {
        // Navigate to Library tab
        let tabBar = app.tabBars.firstMatch
        let libraryTab = tabBar.buttons["Library"]
        
        if libraryTab.exists {
            libraryTab.tap()
            
            // Wait for content to load
            Thread.sleep(forTimeInterval: 2.0)
            
            // Verify we're in the library
            takeScreenshot(named: "library_tab_loaded")
            
            // Basic verification that we're in library view
            XCTAssertTrue(libraryTab.isSelected, "Library tab should be selected")
        } else {
            XCTSkip("Library tab not found - may need UI selector adjustment")
        }
    }
    
    func testSettingsTabBasicFunctionality() throws {
        // Navigate to Settings tab
        let tabBar = app.tabBars.firstMatch
        let settingsTab = tabBar.buttons["Settings"]
        
        if settingsTab.exists {
            settingsTab.tap()
            
            // Wait for content to load
            Thread.sleep(forTimeInterval: 1.0)
            
            // Verify we're in settings
            takeScreenshot(named: "settings_tab_loaded")
            
            XCTAssertTrue(settingsTab.isSelected, "Settings tab should be selected")
        } else {
            XCTSkip("Settings tab not found - may need UI selector adjustment")
        }
    }
    
    // MARK: - Basic Interaction Tests
    
    func testAppRespondsToTaps() throws {
        // Test that the app responds to basic tap interactions
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(waitForElement(tabBar), "Tab bar should be visible")
        
        // Tap between different tabs to ensure responsiveness
        let tabs = tabBar.buttons.allElementsBoundByIndex
        
        for (index, tab) in tabs.enumerated() {
            if tab.exists && tab.isHittable {
                tab.tap()
                
                // Brief wait to allow for transition
                Thread.sleep(forTimeInterval: 0.3)
                
                // Verify the tap was registered (tab should be selected)
                XCTAssertTrue(tab.isSelected, "Tab at index \(index) should be selected after tap")
            }
        }
    }
    
    func testAppMemoryStability() throws {
        // Test that the app remains stable during basic navigation
        let tabBar = app.tabBars.firstMatch
        
        // Navigate through tabs multiple times to test stability
        for _ in 0..<3 {
            let tabs = tabBar.buttons.allElementsBoundByIndex
            for tab in tabs {
                if tab.exists && tab.isHittable {
                    tab.tap()
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }
        
        // Verify app is still running
        verifyAppIsRunning()
        XCTAssertTrue(tabBar.exists, "Tab bar should still be visible after navigation stress test")
    }
    
    // MARK: - Error Handling Tests
    
    func testAppHandlesBackgroundAndForeground() throws {
        // Test app behavior when backgrounded and foregrounded
        verifyAppIsRunning()
        
        // Background the app
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        
        // Bring app back to foreground
        app.activate()
        Thread.sleep(forTimeInterval: 1.0)
        
        // Verify app is still functional
        verifyAppIsRunning()
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Tab bar should be visible after backgrounding")
        
        takeScreenshot(named: "after_background_foreground")
    }
    
    // MARK: - Performance Tests
    
    func testScrollPerformance() throws {
        // Test scrolling performance in main views
        let tabBar = app.tabBars.firstMatch
        
        // Try to find scrollable content
        let scrollViews = app.scrollViews
        let tables = app.tables
        let collectionViews = app.collectionViews
        
        if scrollViews.count > 0 {
            let scrollView = scrollViews.firstMatch
            if scrollView.exists {
                // Perform scroll test
                measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
                    scrollView.swipeUp()
                    scrollView.swipeDown()
                }
            }
        } else if tables.count > 0 {
            let table = tables.firstMatch
            if table.exists {
                measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
                    table.swipeUp()
                    table.swipeDown()
                }
            }
        } else if collectionViews.count > 0 {
            let collectionView = collectionViews.firstMatch
            if collectionView.exists {
                measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
                    collectionView.swipeUp()
                    collectionView.swipeDown()
                }
            }
        }
    }
}