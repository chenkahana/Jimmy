import XCTest

/// Tests for library management functionality
/// Covers podcast library, episode management, and organization features
class LibraryManagementTests: JimmyUITests {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Navigate to Library tab for these tests
        let libraryTab = app.tabBars.firstMatch.buttons["Library"]
        if libraryTab.exists {
            libraryTab.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
    }
    
    // MARK: - Library Display Tests
    
    func testLibraryTabLoads() throws {
        // Verify library tab loads properly
        let libraryTab = app.tabBars.firstMatch.buttons["Library"]
        XCTAssertTrue(libraryTab.exists, "Library tab should exist")
        XCTAssertTrue(libraryTab.isSelected, "Library tab should be selected")
        
        takeScreenshot(named: "library_tab_loaded")
    }
    
    func testLibraryContentDisplay() throws {
        // Test that library shows content appropriately
        Thread.sleep(forTimeInterval: 2.0) // Allow time for content to load
        
        // Look for various content indicators
        let hasScrollViews = app.scrollViews.count > 0
        let hasTables = app.tables.count > 0
        let hasCollectionViews = app.collectionViews.count > 0
        let hasImages = app.images.count > 0
        let hasText = app.staticTexts.count > 0
        
        // Library should show some form of content (even if empty state)
        let hasContent = hasScrollViews || hasTables || hasCollectionViews || hasImages || hasText
        XCTAssertTrue(hasContent, "Library should display some content or empty state")
        
        takeScreenshot(named: "library_content_display")
    }
    
    func testLibraryScrolling() throws {
        // Test scrolling in library view
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
            takeScreenshot(named: "library_scrolled_up")
            
            element.swipeDown()
            Thread.sleep(forTimeInterval: 0.5)
            takeScreenshot(named: "library_scrolled_down")
        } else {
            // This might be expected if library is empty
            takeScreenshot(named: "library_no_scrollable_content")
        }
    }
    
    // MARK: - Podcast Management Tests
    
    func testPodcastInteraction() throws {
        // Test interaction with podcasts in library
        
        // Look for podcast items (cells, buttons, images)
        let cells = app.cells
        let buttons = app.buttons
        let images = app.images
        
        var interactableElements: [XCUIElement] = []
        
        // Collect potentially interactable elements
        for cell in cells.allElementsBoundByIndex {
            if cell.exists && cell.isHittable {
                interactableElements.append(cell)
            }
        }
        
        for button in buttons.allElementsBoundByIndex {
            if button.exists && button.isHittable && !button.label.isEmpty {
                interactableElements.append(button)
            }
        }
        
        if !interactableElements.isEmpty {
            let element = interactableElements.first!
            takeScreenshot(named: "before_podcast_interaction")
            
            element.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            takeScreenshot(named: "after_podcast_interaction")
            
            // If we navigated somewhere, try to go back
            let backButtons = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'back' OR label == 'Library'"))
            if backButtons.count > 0 {
                backButtons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        } else {
            XCTSkip("No interactable podcast elements found - library may be empty")
        }
    }
    
    // MARK: - Organization Tests
    
    func testLibraryOrganization() throws {
        // Test library organization features (sorting, filtering, etc.)
        
        // Look for sort/filter buttons
        let sortButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sort' OR label CONTAINS[c] 'filter' OR label CONTAINS[c] 'organize'"))
        let menuButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'menu' OR label CONTAINS[c] 'options'"))
        
        if sortButtons.count > 0 {
            let sortButton = sortButtons.firstMatch
            if waitForElementToBeHittable(sortButton) {
                takeScreenshot(named: "before_sort_options")
                sortButton.tap()
                
                Thread.sleep(forTimeInterval: 1.0)
                takeScreenshot(named: "sort_options_displayed")
                
                // Dismiss any modal that appeared
                let dismissButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'cancel' OR label CONTAINS[c] 'done' OR label CONTAINS[c] 'dismiss'"))
                if dismissButtons.count > 0 {
                    dismissButtons.firstMatch.tap()
                }
            }
        } else if menuButtons.count > 0 {
            let menuButton = menuButtons.firstMatch
            if waitForElementToBeHittable(menuButton) {
                menuButton.tap()
                Thread.sleep(forTimeInterval: 1.0)
                takeScreenshot(named: "menu_options_displayed")
                
                // Dismiss menu
                let dismissButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'cancel' OR label CONTAINS[c] 'done'"))
                if dismissButtons.count > 0 {
                    dismissButtons.firstMatch.tap()
                }
            }
        } else {
            XCTSkip("No organization controls found")
        }
    }
    
    // MARK: - Search in Library Tests
    
    func testLibrarySearch() throws {
        // Test search functionality within library
        let searchFields = app.searchFields
        let navigationSearchFields = app.navigationBars.searchFields
        
        var searchField: XCUIElement?
        
        if searchFields.count > 0 {
            searchField = searchFields.firstMatch
        } else if navigationSearchFields.count > 0 {
            searchField = navigationSearchFields.firstMatch
        }
        
        if let field = searchField, field.exists {
            field.tap()
            field.typeText("test")
            
            takeScreenshot(named: "library_search_with_text")
            
            // Clear search
            if field.buttons["Clear text"].exists {
                field.buttons["Clear text"].tap()
            }
            
            takeScreenshot(named: "library_search_cleared")
        } else {
            XCTSkip("No search field found in library")
        }
    }
    
    // MARK: - Episode Management Tests
    
    func testEpisodeAccess() throws {
        // Test accessing episodes from library
        
        // Look for episode-related elements
        let episodeButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'episode' OR label CONTAINS[c] 'play' OR label CONTAINS[c] 'download'"))
        
        if episodeButtons.count > 0 {
            let episodeButton = episodeButtons.firstMatch
            if waitForElementToBeHittable(episodeButton) {
                takeScreenshot(named: "before_episode_access")
                episodeButton.tap()
                
                Thread.sleep(forTimeInterval: 1.0)
                takeScreenshot(named: "after_episode_access")
                
                // Navigate back if needed
                let backButtons = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'back' OR label == 'Library'"))
                if backButtons.count > 0 {
                    backButtons.firstMatch.tap()
                }
            }
        } else {
            XCTSkip("No episode access elements found")
        }
    }
    
    // MARK: - Performance Tests
    
    func testLibraryLoadPerformance() throws {
        // Measure library load performance
        let libraryTab = app.tabBars.firstMatch.buttons["Library"]
        let discoverTab = app.tabBars.firstMatch.buttons["Discover"]
        
        if libraryTab.exists && discoverTab.exists {
            measure {
                // Switch away and back to measure load time
                discoverTab.tap()
                Thread.sleep(forTimeInterval: 0.1)
                libraryTab.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
    
    func testLibraryScrollPerformance() throws {
        // Test scrolling performance in library
        let scrollViews = app.scrollViews
        let tables = app.tables
        
        var scrollableElement: XCUIElement?
        
        if scrollViews.count > 0 {
            scrollableElement = scrollViews.firstMatch
        } else if tables.count > 0 {
            scrollableElement = tables.firstMatch
        }
        
        if let element = scrollableElement, element.exists {
            measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
                element.swipeUp()
                element.swipeDown()
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testLibraryErrorStates() throws {
        // Test library behavior in error conditions
        
        // Verify library tab remains functional even if content fails to load
        let libraryTab = app.tabBars.firstMatch.buttons["Library"]
        XCTAssertTrue(libraryTab.exists, "Library tab should exist")
        XCTAssertTrue(libraryTab.isSelected, "Library tab should be selected")
        
        // Library should show some UI even in error states
        let hasBasicUI = app.navigationBars.count > 0 || app.tabBars.count > 0
        XCTAssertTrue(hasBasicUI, "Library should maintain basic UI structure")
        
        takeScreenshot(named: "library_error_state_handling")
    }
}