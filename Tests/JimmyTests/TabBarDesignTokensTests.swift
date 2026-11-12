//
//  TabBarDesignTokensTests.swift
//  JimmyTests
//
//  Unit tests for TabBarDesignTokens
//

import XCTest
import SwiftUI
@testable import Jimmy

@MainActor
final class TabBarDesignTokensTests: XCTestCase {
    
    // MARK: - Size Class Tests
    
    func testCompactSizeClassMetrics() {
        let tokens = TabBarDesignTokens(sizeClass: .compact)
        
        XCTAssertEqual(tokens.barHeight, 56, "Compact bar height should be 56pt")
        XCTAssertEqual(tokens.pillCornerRadius, 24, "Compact pill corner radius should be 24pt")
        XCTAssertEqual(tokens.horizontalEdgeInset, 14, "Compact horizontal edge inset should be 14pt")
        XCTAssertEqual(tokens.itemInterSpacing, 22, "Compact item spacing should be 22pt")
        XCTAssertEqual(tokens.iconPointSize, 20, "Compact icon size should be 20pt")
        XCTAssertEqual(tokens.searchPillHeight, 34, "Compact search pill height should be 34pt")
        XCTAssertEqual(tokens.searchPillHorizontalPadding, 12, "Compact search pill padding should be 12pt")
    }
    
    func testRegularSizeClassMetrics() {
        let tokens = TabBarDesignTokens(sizeClass: .regular)
        
        XCTAssertEqual(tokens.barHeight, 62, "Regular bar height should be 62pt")
        XCTAssertEqual(tokens.pillCornerRadius, 28, "Regular pill corner radius should be 28pt")
        XCTAssertEqual(tokens.horizontalEdgeInset, 16, "Regular horizontal edge inset should be 16pt")
        XCTAssertEqual(tokens.itemInterSpacing, 26, "Regular item spacing should be 26pt")
        XCTAssertEqual(tokens.iconPointSize, 22, "Regular icon size should be 22pt")
        XCTAssertEqual(tokens.searchPillHeight, 36, "Regular search pill height should be 36pt")
        XCTAssertEqual(tokens.searchPillHorizontalPadding, 14, "Regular search pill padding should be 14pt")
    }
    
    // MARK: - Constant Values Tests
    
    func testItemMinHitSize() {
        let tokens = TabBarDesignTokens()
        
        XCTAssertEqual(tokens.itemMinHitSize.width, 44, "Min hit width should be 44pt")
        XCTAssertEqual(tokens.itemMinHitSize.height, 44, "Min hit height should be 44pt")
    }
    
    func testOpacityValues() {
        let tokens = TabBarDesignTokens()
        
        XCTAssertEqual(tokens.unselectedOpacity, 0.78, accuracy: 0.01, "Unselected opacity should be 0.78")
        XCTAssertEqual(tokens.selectedOpacity, 1.0, accuracy: 0.01, "Selected opacity should be 1.0")
    }
    
    func testFontWeights() {
        let tokens = TabBarDesignTokens()
        
        XCTAssertEqual(tokens.iconWeightUnselected, .regular, "Unselected icon weight should be regular")
        XCTAssertEqual(tokens.iconWeightSelected, .semibold, "Selected icon weight should be semibold")
        XCTAssertEqual(tokens.labelWeightUnselected, .regular, "Unselected label weight should be regular")
        XCTAssertEqual(tokens.labelWeightSelected, .semibold, "Selected label weight should be semibold")
    }
    
    // MARK: - Selection Capsule Tests
    
    func testCapsuleMetrics() {
        let tokens = TabBarDesignTokens()
        
        XCTAssertEqual(tokens.capsuleFillOpacity, 0.10, accuracy: 0.01, "Capsule fill opacity should be ~10%")
        XCTAssertEqual(tokens.capsuleStrokeWidth, 1.0, "Capsule stroke width should be 1pt")
        XCTAssertEqual(tokens.capsuleStrokeOpacity, 0.14, accuracy: 0.01, "Capsule stroke opacity should be ~14%")
        XCTAssertEqual(tokens.capsuleStrokeOpacityHighContrast, 0.30, accuracy: 0.01, "High contrast stroke should be 30%")
        XCTAssertEqual(tokens.capsuleHorizontalPadding, 9, "Capsule padding should be 9pt")
    }
    
    func testCapsuleStrokeOpacityWithAccessibility() {
        let tokens = TabBarDesignTokens()
        
        let normalOpacity = tokens.capsuleStrokeOpacity(increaseContrast: false)
        let highContrastOpacity = tokens.capsuleStrokeOpacity(increaseContrast: true)
        
        XCTAssertEqual(normalOpacity, 0.14, accuracy: 0.01, "Normal contrast should be ~14%")
        XCTAssertEqual(highContrastOpacity, 0.30, accuracy: 0.01, "High contrast should be 30%")
        XCTAssertGreaterThan(highContrastOpacity, normalOpacity, "High contrast should be greater than normal")
    }
    
    // MARK: - Animation Tests
    
    func testAnimationDurations() {
        let tokens = TabBarDesignTokens()
        
        XCTAssertEqual(tokens.animationDurationMs, 200, "Animation duration should be 200ms")
        XCTAssertEqual(tokens.springResponse, 0.35, accuracy: 0.01, "Spring response should be 0.35")
        XCTAssertEqual(tokens.springDamping, 0.85, accuracy: 0.01, "Spring damping should be 0.85")
    }
    
    func testMinimizeRegrowAnimations() {
        let tokens = TabBarDesignTokens()
        
        XCTAssertEqual(tokens.minimizeSpringResponse, 0.35, accuracy: 0.01, "Minimize response should be 0.35")
        XCTAssertEqual(tokens.minimizeSpringDamping, 0.85, accuracy: 0.01, "Minimize damping should be 0.85")
        XCTAssertEqual(tokens.regrowSpringResponse, 0.4, accuracy: 0.01, "Regrow response should be 0.4")
        XCTAssertEqual(tokens.regrowSpringDamping, 0.8, accuracy: 0.01, "Regrow damping should be 0.8")
    }
    
    func testAnimationWithReduceMotion() {
        let tokens = TabBarDesignTokens()
        
        // We can't directly test Animation equality, but we can verify the method returns without crashing
        let normalAnimation = tokens.animation(reduceMotion: false)
        let reducedAnimation = tokens.animation(reduceMotion: true)
        
        XCTAssertNotNil(normalAnimation, "Normal animation should not be nil")
        XCTAssertNotNil(reducedAnimation, "Reduced motion animation should not be nil")
    }
    
    // MARK: - Search Pill Tests
    
    func testSearchPillMetrics() {
        let tokens = TabBarDesignTokens()
        
        XCTAssertEqual(tokens.searchPillCornerRadius, 18, "Search pill corner radius should be 18pt")
        XCTAssertEqual(tokens.searchPillOpacity, 0.92, accuracy: 0.01, "Search pill opacity should be 0.92")
        XCTAssertEqual(tokens.searchPillPlaceholder, "Search", "Search pill placeholder should be 'Search'")
    }
    
    // MARK: - Default Initialization Tests
    
    func testDefaultInitialization() {
        let tokens = TabBarDesignTokens()
        
        // Default should be compact
        XCTAssertEqual(tokens.sizeClass, .compact, "Default size class should be compact")
        XCTAssertEqual(tokens.barHeight, 56, "Default bar height should match compact")
    }
    
    // MARK: - Value Range Tests
    
    func testAnimationDurationInRange() {
        let tokens = TabBarDesignTokens()
        
        // Animation should be in 180-220ms range
        XCTAssertGreaterThanOrEqual(tokens.animationDurationMs, 180, "Animation should be >= 180ms")
        XCTAssertLessThanOrEqual(tokens.animationDurationMs, 220, "Animation should be <= 220ms")
    }
    
    func testSearchPillHeightInRange() {
        let compactTokens = TabBarDesignTokens(sizeClass: .compact)
        let regularTokens = TabBarDesignTokens(sizeClass: .regular)
        
        // Search pill should be in 32-36pt range
        XCTAssertGreaterThanOrEqual(compactTokens.searchPillHeight, 32, "Compact pill should be >= 32pt")
        XCTAssertLessThanOrEqual(compactTokens.searchPillHeight, 36, "Compact pill should be <= 36pt")
        XCTAssertGreaterThanOrEqual(regularTokens.searchPillHeight, 32, "Regular pill should be >= 32pt")
        XCTAssertLessThanOrEqual(regularTokens.searchPillHeight, 36, "Regular pill should be <= 36pt")
    }
}
