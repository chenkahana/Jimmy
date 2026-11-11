import XCTest

/// Base class for all Jimmy UI tests
/// Provides common setup, teardown, and utility methods
class JimmyUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launch()
        
        // Wait for app to be ready
        let appReadyTimeout: TimeInterval = 30.0
        let appIsReady = app.wait(for: .runningForeground, timeout: appReadyTimeout)
        XCTAssertTrue(appIsReady, "App should be running in foreground within \(appReadyTimeout) seconds")
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        app.terminate()
        app = nil
    }
    
    // MARK: - Helper Methods
    
    /// Wait for an element to exist with timeout
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 10.0) -> Bool {
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    /// Wait for an element to be hittable with timeout
    func waitForElementToBeHittable(_ element: XCUIElement, timeout: TimeInterval = 10.0) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    /// Take a screenshot with a descriptive name
    func takeScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    /// Verify app is in expected state
    func verifyAppIsRunning() {
        XCTAssertTrue(app.state == .runningForeground, "App should be running in foreground")
    }
}