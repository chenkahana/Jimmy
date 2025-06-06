#if !os(Linux)
import XCTest
@testable import Jimmy

final class QueueViewModelTests: XCTestCase {
    override func setUp() async throws {
        QueueViewModel.shared.queue.removeAll()
    }

    func testAddToQueuePreventsDuplicates() {
        let episode = Episode(id: UUID(), title: "Ep", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: nil, publishedDate: nil, localFileURL: nil)
        QueueViewModel.shared.addToQueue(episode)
        QueueViewModel.shared.addToQueue(episode)
        XCTAssertEqual(QueueViewModel.shared.queue.count, 1)
    }

    func testMoveToEndOfQueue() {
        let e1 = Episode(id: UUID(), title: "1", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: nil, publishedDate: nil, localFileURL: nil)
        let e2 = Episode(id: UUID(), title: "2", artworkURL: nil, audioURL: nil, description: nil, played: false, podcastID: nil, publishedDate: nil, localFileURL: nil)
        QueueViewModel.shared.addToQueue(e1)
        QueueViewModel.shared.addToQueue(e2)
        QueueViewModel.shared.moveToEndOfQueue(e1)
        XCTAssertEqual(QueueViewModel.shared.queue.last?.id, e1.id)
    }
}
#endif
