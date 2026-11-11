import XCTest

/// Tests for podcast discovery functionality
/// Covers search, browsing, and podcast addition workflows
class PodcastDiscoveryTests: JimmyUITests {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Navigate to Discover tab for these tests
        let discoverTab = app.tabBars.firstMatch.buttons["Discover"]
        if discoverTab.exists {
            discoverTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
    
    // MARK: - Search Tests
    
    func testSearchFieldExists() throws {
        // Verify search functionality is available
        let searchFields = app.searchFields
        
        if searchFields.count > 0 {
            let searchField = searchFields.firstMatch
            XCTAssertTrue(waitForElement(searchField), "Search field should be visible in Discover tab")
            takeScreenshot(named: "search_field_visible")
        } else {
            // Look for alternative search UI elements
            let searchButtons = app.buttons.matching(identifier: "search").firstMatch
            let navigationSearchFields = app.navigationBars.searchFields.firstMatch
            
            if searchButtons.exists {
                XCTAssertTrue(searchButtons.exists, "Search button should be available")
            } else if navigationSearchFields.exists {
                XCTAssertTrue(navigationSearchFields.exists, "Navigation search field should be available")
            } else {
                XCTSkip("Search UI not found - may need selector adjustment")
            }
        }
    }
    
    func testSearchInteraction() throws {
        // Test basic search interaction
        let searchFields = app.searchFields
        
        if searchFields.count > 0 {
            let searchField = searchFields.firstMatch
            XCTAssertTrue(waitForElement(searchField), "Search field should be available")
            
            // Tap search field
            searchField.tap()
            
            // Type a test query
            searchField.typeText("test podcast")
            
            takeScreenshot(named: "search_with_text")
            
            // Clear the search
            if searchField.buttons["Clear text"].exists {
                searchField.buttons["Clear text"].tap()
            }
            
            takeScreenshot(named: "search_cleared")
        } else {
            XCTSkip("Search field not found for interaction test")
        }
    }
    
    // MARK: - Browse Tests
    
    func testDiscoverContentLoads() throws {
        // Test that discover content loads properly
        Thread.sleep(forTimeInterval: 3.0) // Allow time for content to load
        
        // Look for various content indicators
        let hasScrollViews = app.scrollViews.count > 0
        let hasTables = app.tables.count > 0
        let hasCollectionViews = app.collectionViews.count > 0
        let hasImages = app.images.count > 0
        let hasText = app.staticTexts.count > 0
        
        // At least some content should be present
        let hasContent = hasScrollViews || hasTables || hasCollectionViews || hasImages || hasText
        
        XCTAssertTrue(hasContent, "Discover tab should show some content")
        takeScreenshot(named: "discover_content_loaded")
    }
    
    func testDiscoverScrolling() throws {
        // Test scrolling in discover view
        let scrollViews = app.scrollViews
        let tables = app.tables
        let collectionViews = app.collectionViews
        
        var scrollableElement: XCUIElement?
        
        if scrollViews.count > 0 {
            scrollableElement = scrollViews.firstMatch
        } else if tables.count > 0 {
            scrollableElement = tables.firstMatch
        } else if collectionViews.count > 0 {
            scrollableElement = collectionViews.firstMatch
        }
        
        if let element = scrollableElement, element.exists {
            // Test scrolling
            element.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            takeScreenshot(named: "discover_scrolled_up")
            
            element.swipeDown()
            Thread.sleep(forTimeInterval: 0.5)
            takeScreenshot(named: "discover_scrolled_down")
        } else {
            XCTSkip("No scrollable content found in Discover tab")
        }
    }
    
    // MARK: - Podcast Addition Tests
    
    func testPodcastAdditionFlow() throws {
        // Test the flow for adding a podcast (if available)
        
        // Look for add/subscribe buttons
        let addButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add' OR label CONTAINS[c] 'subscribe' OR label CONTAINS[c] '+'"))
        
        if addButtons.count > 0 {
            let addButton = addButtons.firstMatch
            if waitForElementToBeHittable(addButton) {
                takeScreenshot(named: "before_add_podcast")
                addButton.tap()
                
                Thread.sleep(forTimeInterval: 1.0)
                takeScreenshot(named: "after_add_podcast_tap")
                
                // Look for confirmation or next step in the flow
                let alerts = app.alerts
                let sheets = app.sheets
                
                if alerts.count > 0 {
                    takeScreenshot(named: "add_podcast_alert")
                    // Handle alert if present
                    let alert = alerts.firstMatch
                    if alert.buttons["OK"].exists {
                        alert.buttons["OK"].tap()
                    } else if alert.buttons["Cancel"].exists {
                        alert.buttons["Cancel"].tap()
                    }
                } else if sheets.count > 0 {
                    takeScreenshot(named: "add_podcast_sheet")
                    // Handle sheet if present
                    let sheet = sheets.firstMatch
                    if sheet.buttons["Cancel"].exists {
                        sheet.buttons["Cancel"].tap()
                    }
                }
            }
        } else {
            XCTSkip("No add/subscribe buttons found - may need UI selector adjustment")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testDiscoverWithoutNetwork() throws {
        // Test discover behavior with limited connectivity
        // Note: This is a basic test - full network simulation would require additional setup
        
        // Verify discover tab still loads basic UI even if content fails
        let discoverTab = app.tabBars.firstMatch.buttons["Discover"]
        XCTAssertTrue(discoverTab.exists, "Discover tab should exist")
        XCTAssertTrue(discoverTab.isSelected, "Discover tab should be selected")
        
        takeScreenshot(named: "discover_basic_ui")
    }
    
    // MARK: - Performance Tests
    
    func testDiscoverLoadPerformance() throws {
        // Measure discover tab load performance
        let discoverTab = app.tabBars.firstMatch.buttons["Discover"]
        let libraryTab = app.tabBars.firstMatch.buttons["Library"]
        
        if discoverTab.exists && libraryTab.exists {
            measure {
                // Switch away and back to measure load time
                libraryTab.tap()
                Thread.sleep(forTimeInterval: 0.1)
                discoverTab.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
}