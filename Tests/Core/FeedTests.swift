import XCTest

@testable import PodcastCore

final class FeedTests: XCTestCase {
  func testParsingAndUnsafeEnclosures() throws {
    let xml =
      "<rss><channel><item><title>One &amp; two</title><guid>one</guid><enclosure url='https://example.com/one.mp3'/></item><item><title>Unsafe</title><enclosure url='file:///etc/passwd'/></item></channel></rss>"
    let episodes = try FeedParser().parse(Data(xml.utf8))
    XCTAssertEqual(episodes.count, 1)
    XCTAssertEqual(episodes[0].title, "One & two")
  }
  func testRefreshKeepsResumeAndOfflineFiles() {
    var episode = Episode(
      id: "one", title: "Old", audio: URL(string: "https://example.com/a.mp3")!, summary: "")
    episode.file = "one.mp3"
    episode.position = 25
    let fresh = Episode(id: "one", title: "New", audio: episode.audio, summary: "")
    XCTAssertEqual(mergeEpisodes([fresh], with: [episode])[0].position, 25)
    XCTAssertEqual(mergeEpisodes([], with: [episode]), [episode])
  }
}
