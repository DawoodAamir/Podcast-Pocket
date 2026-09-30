import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif
struct Episode: Codable, Identifiable, Equatable {
  let id: String
  let title: String
  let audio: URL
  var summary: String
  var position: Double = 0
  var file: String?
}
final class FeedParser: NSObject, XMLParserDelegate {
  private var inside = false, field = "", text = "", title = "", summary = "", guid = "",
    audio: URL?
  private var episodes: [Episode] = []
  func parse(_ data: Data) throws -> [Episode] {
    episodes = []
    inside = false
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
    return episodes
  }
  func parser(
    _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]
  ) {
    if element == "item" {
      inside = true
      title = ""
      summary = ""
      guid = ""
      audio = nil
    }
    if inside {
      field = element
      text = ""
      if element == "enclosure", let value = attributes["url"], let url = URL(string: value),
        url.scheme == "https", url.user == nil, url.password == nil
      {
        audio = url
      }
    }
  }
  func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    text += String(data: CDATABlock, encoding: .utf8) ?? ""
  }
  func parser(
    _ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
    qualifiedName: String?
  ) {
    if inside {
      let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if element == "title" { title = clean }
      if element == "description" { summary = clean }
      if element == "guid" { guid = clean }
      if element == "item" {
        if let audio, !title.isEmpty {
          let id = guid.isEmpty ? audio.absoluteString : guid
          if !episodes.contains(where: { $0.id == id }) {
            episodes.append(Episode(id: id, title: title, audio: audio, summary: summary))
          }
        }
        inside = false
      }
    }
    text = ""
  }
}
func mergeEpisodes(_ new: [Episode], with old: [Episode]) -> [Episode] {
  new.map { episode in
    var copy = episode
    if let saved = old.first(where: { $0.id == copy.id }) {
      copy.position = saved.position
      copy.file = saved.file
    }
    return copy
  } + old.filter { previous in previous.file != nil && !new.contains { $0.id == previous.id } }
}
