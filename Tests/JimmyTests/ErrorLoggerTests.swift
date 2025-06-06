#if !os(Linux)
import XCTest
@testable import Jimmy

final class ErrorLoggerTests: XCTestCase {
    func testLogFileCreationAndAppend() throws {
        let logger = ErrorLogger.shared
        let fileURL = logger.exportLogFile()
        // remove existing file if any
        try? FileManager.default.removeItem(at: fileURL)

        let message = "Test error"
        logger.log(message)

        let contents = try String(contentsOf: fileURL)
        XCTAssertTrue(contents.contains(message))

        // Clean up
        try? FileManager.default.removeItem(at: fileURL)
    }
}
#endif
