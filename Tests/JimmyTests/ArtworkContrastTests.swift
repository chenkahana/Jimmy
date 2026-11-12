import XCTest
@testable import Jimmy

final class ArtworkContrastTests: XCTestCase {
    func testLuminanceAndContrastMatchWCAG() {
        XCTAssertEqual(ArtworkContrast.white.luminance, 1, accuracy: 0.0001)
        XCTAssertEqual(ArtworkContrast.black.luminance, 0, accuracy: 0.0001)
        XCTAssertEqual(ArtworkContrast.black.contrast(with: .white), 21, accuracy: 0.0001)
        // #777777 on white is the textbook 4.48:1.
        let gray = ArtworkContrast(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255)
        XCTAssertEqual(gray.contrast(with: .white), 4.48, accuracy: 0.01)
    }

    func testDarkColorGetsWhiteText() {
        let navy = ArtworkContrast(red: 0.1, green: 0.15, blue: 0.4)
        XCTAssertEqual(navy.text, .white)
        XCTAssertEqual(navy.colorScheme, .dark)
        XCTAssertEqual(navy.usable, navy)
    }

    func testLightColorGetsBlackText() {
        let orange = ArtworkContrast(red: 0.95, green: 0.55, blue: 0.1)
        XCTAssertEqual(orange.text, .black)
        XCTAssertEqual(orange.colorScheme, .light)
        XCTAssertEqual(orange.usable, orange)
    }

    func testNearWhiteAndNearBlackAreSkipped() {
        XCTAssertNil(ArtworkContrast(red: 0.97, green: 0.97, blue: 0.96).usable)
        // ArtworkColorExtractor's quantized white.
        XCTAssertNil(ArtworkContrast(red: 224 / 255, green: 224 / 255, blue: 224 / 255).usable)
        XCTAssertNil(ArtworkContrast(red: 0.05, green: 0.05, blue: 0.06).usable)
    }

    func testEveryUsableColorPassesTextContrast() {
        let steps = stride(from: 0.0, through: 1.0, by: 0.125)
        for red in steps {
            for green in steps {
                for blue in steps {
                    guard let band = ArtworkContrast(red: red, green: green, blue: blue).usable else { continue }
                    XCTAssertGreaterThanOrEqual(band.contrast(with: band.text), 4.5, "\(red) \(green) \(blue)")
                }
            }
        }
    }
}
