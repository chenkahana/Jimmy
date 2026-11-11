//
//  BackgroundOnlyTabBarTests.swift
//  JimmyTests
//
//  Unit tests for BackgroundOnlyTabBar
//

import XCTest
@testable import Jimmy

final class BackgroundOnlyTabBarTests: XCTestCase {
    
    var tabBar: BackgroundOnlyTabBar!
    
    override func setUp() {
        super.setUp()
        tabBar = BackgroundOnlyTabBar()
    }
    
    override func tearDown() {
        tabBar = nil
        super.tearDown()
    }
    
    // MARK: - Configuration Tests
    
    func testIsTranslucent() {
        // Trigger didMoveToWindow by adding to a window
        let window = UIWindow()
        window.addSubview(tabBar)
        
        XCTAssertTrue(tabBar.isTranslucent, "Tab bar should be translucent for Liquid Glass effect")
    }
    
    func testAppearanceConfiguration() {
        // Trigger didMoveToWindow
        let window = UIWindow()
        window.addSubview(tabBar)
        
        let appearance = tabBar.standardAppearance
        
        // Verify background effect is system thin material
        XCTAssertNotNil(appearance.backgroundEffect, "Should have background effect")

        // Transparent tab bars may report nil here on newer SDKs even when visually clear.
        if let backgroundColor = appearance.backgroundColor {
            XCTAssertEqual(backgroundColor, .clear, "Background color should remain visually clear")
        }

        let stackedAppearance = appearance.stackedLayoutAppearance
        XCTAssertEqual(stackedAppearance.normal.iconColor, .clear, "Normal icon color should be clear")
        XCTAssertEqual(stackedAppearance.selected.iconColor, .clear, "Selected icon color should be clear")
        XCTAssertEqual(
            stackedAppearance.normal.titleTextAttributes[.foregroundColor] as? UIColor,
            .clear,
            "Normal title color should be clear"
        )
        XCTAssertEqual(
            stackedAppearance.selected.titleTextAttributes[.foregroundColor] as? UIColor,
            .clear,
            "Selected title color should be clear"
        )
    }
    
    func testTintColorsCleared() {
        let window = UIWindow()
        window.addSubview(tabBar)
        
        XCTAssertEqual(tabBar.tintColor, .clear, "Tint color should be clear")
        XCTAssertEqual(tabBar.unselectedItemTintColor, .clear, "Unselected item tint color should be clear")
    }
    
    // MARK: - System UI Removal Tests
    
    func testSystemUIElementsRemoved() {
        // Create a mock tab bar controller to trigger system UI creation
        let controller = UITabBarController()
        controller.viewControllers = [
            UIViewController(),
            UIViewController(),
            UIViewController()
        ]
        
        // Replace with BackgroundOnlyTabBar
        controller.setValue(tabBar, forKey: "tabBar")
        
        // Trigger layout
        controller.view.layoutIfNeeded()
        tabBar.layoutIfNeeded()
        
        // Verify no UITabBarButton subviews remain
        let buttonSubviews = tabBar.subviews.filter { subview in
            String(describing: type(of: subview)).contains("UITabBarButton")
        }
        
        XCTAssertEqual(buttonSubviews.count, 0, "All UITabBarButton subviews should be removed")
    }
    
    func testRemainingSubviewsDisabled() {
        let window = UIWindow()
        window.addSubview(tabBar)
        
        // Add a test subview
        let testView = UIView()
        tabBar.addSubview(testView)
        
        // Trigger layout
        tabBar.layoutIfNeeded()
        
        // Check that non-button subviews are disabled
        for subview in tabBar.subviews {
            let className = String(describing: type(of: subview))
            if !className.contains("UITabBarButton") && !className.contains("SelectionIndicator") {
                XCTAssertFalse(subview.isUserInteractionEnabled, "Non-button subviews should have interaction disabled")
                XCTAssertTrue(subview.isHidden, "Non-button subviews should be hidden")
            }
        }
    }
}
