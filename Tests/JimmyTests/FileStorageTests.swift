import XCTest
@testable import JimmyUtilities

private struct Dummy: Codable, Equatable {
    let id: Int
    let message: String
}

final class FileStorageTests: XCTestCase {
    func testSaveAndLoad() throws {
        let object = Dummy(id: 1, message: "Hello")
        let filename = "dummy.json"
        // Ensure clean state
        _ = FileStorage.shared.delete(filename)

        // Save object
        XCTAssertTrue(FileStorage.shared.save(object, to: filename))

        // Load object
        let loaded: Dummy? = FileStorage.shared.load(Dummy.self, from: filename)
        XCTAssertEqual(loaded, object)

        // Clean up
        _ = FileStorage.shared.delete(filename)
    }
}
