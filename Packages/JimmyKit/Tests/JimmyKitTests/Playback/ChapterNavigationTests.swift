import Foundation
import Testing
@testable import JimmyKit

@MainActor
struct ChapterNavigationTests {
    private let chapters = [
        Chapter(start: 0, title: "Intro"),
        Chapter(start: 100, title: "Middle"),
        Chapter(start: 300, title: "Outro"),
    ]

    private func makeSUT() -> (Playback, FakePlayerEngine) {
        let engine = FakePlayerEngine()
        let playback = Playback(engine: engine, progressStore: FakeProgressStore(), queueSource: FakeQueueSource())
        return (playback, engine)
    }

    @Test func currentChapterTracksPositionAfterLoad() async {
        let (playback, _) = makeSUT()
        let episode = Episode(title: "A", audioURL: URL(string: "https://example.com/a.mp3"), duration: 1_000)

        await playback.load(episode: episode, chapters: chapters)

        #expect(playback.currentChapter == chapters[0])
    }

    @Test func currentChapterUpdatesAsPositionCrossesBoundaries() async {
        let (playback, _) = makeSUT()
        let episode = Episode(title: "A", audioURL: URL(string: "https://example.com/a.mp3"), duration: 1_000)
        await playback.load(episode: episode, chapters: chapters)

        await playback.seek(to: 150)
        #expect(playback.currentChapter == chapters[1])

        await playback.seek(to: 300)
        #expect(playback.currentChapter == chapters[2])

        await playback.seek(to: 50)
        #expect(playback.currentChapter == chapters[0])
    }

    @Test func nextAndPreviousChapterNavigate() async {
        let (playback, _) = makeSUT()
        let episode = Episode(title: "A", audioURL: URL(string: "https://example.com/a.mp3"), duration: 1_000)
        await playback.load(episode: episode, chapters: chapters)
        await playback.seek(to: 150)

        #expect(playback.nextChapter() == chapters[2])
        #expect(playback.previousChapter() == chapters[0])

        await playback.skipToNextChapter()
        #expect(playback.currentChapter == chapters[2])
        #expect(playback.position == chapters[2].start)

        await playback.skipToPreviousChapter()
        #expect(playback.currentChapter == chapters[1])
        #expect(playback.position == chapters[1].start)
    }

    @Test func noNextChapterPastTheLastOne() async {
        let (playback, _) = makeSUT()
        let episode = Episode(title: "A", audioURL: URL(string: "https://example.com/a.mp3"), duration: 1_000)
        await playback.load(episode: episode, chapters: chapters)
        await playback.seek(to: 300)

        #expect(playback.nextChapter() == nil)
    }

    @Test func noPreviousChapterBeforeTheFirstOne() async {
        let (playback, _) = makeSUT()
        let episode = Episode(title: "A", audioURL: URL(string: "https://example.com/a.mp3"), duration: 1_000)
        await playback.load(episode: episode, chapters: chapters)

        #expect(playback.previousChapter() == nil)
    }
}
