import XCTest
@testable import Jimmy

@MainActor
final class TabBarPerformanceTests: XCTestCase {
    
    var stateManager: TabBarStateManagerV3!
    
    override func setUp() async throws {
        stateManager = TabBarStateManagerV3()
    }
    
    override func tearDown() async throws {
        stateManager = nil
    }
    
    // MARK: - State Transition Performance
    
    func testSearchActivationPerformance() {
        measure {
            for _ in 0..<100 {
                stateManager.handleSearchActivation()
            }
        }
    }
    
    func testSearchDismissalPerformance() {
        measure {
            for _ in 0..<100 {
                stateManager.handleSearchDismissal()
            }
        }
    }
    
    func testRapidTabSwitchingPerformance() {
        measure {
            for i in 0..<100 {
                stateManager.selectedTab = i % 5
            }
        }
    }
    
    // MARK: - State Update Performance
    
    func testStateUpdatePerformance() {
        let states: [TabBarState] = [.full, .minimized, .withAccessory(height: 50)]
        
        measure {
            for _ in 0..<100 {
                for state in states {
                    stateManager.updateState(state, animated: false)
                }
            }
        }
    }
    
    // MARK: - Computed Property Performance
    
    func testTabBarHeightCalculationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = stateManager.tabBarHeight
            }
        }
    }
    
    func testShouldShowLabelsCalculationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = stateManager.shouldShowLabels
            }
        }
    }
    
    func testShouldShowSelectionIndicatorCalculationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = stateManager.shouldShowSelectionIndicator
            }
        }
    }
    
    // MARK: - Memory Performance
    
    func testMemoryUsageDuringRapidStateChanges() {
        measure(metrics: [XCTMemoryMetric()]) {
            for _ in 0..<1000 {
                stateManager.handleSearchActivation()
                stateManager.handleSearchDismissal()
            }
        }
    }
    
    // MARK: - Animation Parameter Performance
    
    func testAnimationParameterCalculationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = TabBarAnimationsV3.animation(reduceMotion: false, type: .minimization)
                _ = TabBarAnimationsV3.animation(reduceMotion: false, type: .restoration)
                _ = TabBarAnimationsV3.animation(reduceMotion: false, type: .selection)
                _ = TabBarAnimationsV3.animation(reduceMotion: false, type: .press)
            }
        }
    }
    
    // MARK: - Color Calculation Performance
    
    func testColorCalculationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = TabBarColorsV3.iconColor(isSelected: true)
                _ = TabBarColorsV3.iconColor(isSelected: false)
                _ = TabBarColorsV3.labelColor(isSelected: true)
                _ = TabBarColorsV3.labelColor(isSelected: false)
                _ = TabBarColorsV3.borderOpacity(lightMode: true, reduceTransparency: false)
                _ = TabBarColorsV3.borderOpacity(lightMode: false, reduceTransparency: true)
            }
        }
    }
    
    // MARK: - Frame Rate Tests
    
    func testAnimationFrameRateTarget() {
        // Target: 120fps on ProMotion (8.33ms per frame)
        // Target: 60fps on standard (16.67ms per frame)
        
        let targetFrameTime: TimeInterval = 1.0 / 120.0 // 8.33ms for 120fps
        
        measure {
            let startTime = Date()
            
            for _ in 0..<120 {
                stateManager.updateState(.minimized, animated: false)
                stateManager.updateState(.full, animated: false)
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let averageFrameTime = elapsed / 240.0
            
            XCTAssertLessThan(averageFrameTime, targetFrameTime * 2, "Frame time should be reasonable for 120fps")
        }
    }
    
    // MARK: - Stress Tests
    
    func testConcurrentStateUpdates() {
        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            // This state manager is main-actor isolated, so "concurrent" callers serialize in practice.
            // Stress the hot path directly instead of blocking the main actor on a DispatchGroup.
            for _ in 0..<1_000 {
                stateManager.updateState(.minimized, animated: false)
                stateManager.updateState(.full, animated: false)
            }
        }
    }
}
