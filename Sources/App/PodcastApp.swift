import AVFoundation
import MediaPlayer
import SwiftUI

final class Downloads: NSObject, URLSessionDownloadDelegate {
  static let shared = Downloads()
  var onSaved: ((String, String) -> Void)?
  var onFailure: ((String, String) -> Void)?
  var backgroundCompletion: (() -> Void)?
  static var manifest: URL { directory.appendingPathComponent("manifest.json") }
  static func savedDownloads() -> [String: String] {
    (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifest))) ?? [:]
  }
  lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: "com.dd.podcastpocket.downloads")
    config.isDiscretionary = false
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()
  static let directory = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
      (ProcessInfo.processInfo.environment["PORTFOLIO_UI_TEST"].map { "UITests/" + $0 + "/" } ?? "")
        + "PodcastPocket/Audio", isDirectory: true)
  func start(_ episode: Episode) {
    let task = session.downloadTask(with: episode.audio)
    task.taskDescription = episode.id
    task.resume()
  }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    let id = downloadTask.taskDescription ?? ""
    do {
      guard let response = downloadTask.response as? HTTPURLResponse,
        (200..<300).contains(response.statusCode), response.url?.scheme == "https"
      else { throw URLError(.badServerResponse) }
      let bytes = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard bytes > 0, bytes < 500_000_000 else { throw CocoaError(.fileReadTooLarge) }
      try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
      let file =
        UUID().uuidString + "."
        + (response.url?.pathExtension.isEmpty == false ? response.url!.pathExtension : "mp3")
      try FileManager.default.moveItem(
        at: location, to: Self.directory.appendingPathComponent(file))
      DispatchQueue.main.async { self.onSaved?(id, file) }
    } catch { DispatchQueue.main.async { self.onFailure?(id, error.localizedDescription) } }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error {
      DispatchQueue.main.async {
        self.onFailure?(task.taskDescription ?? "", error.localizedDescription)
      }
    }
  }
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      self.backgroundCompletion?()
      self.backgroundCompletion = nil
    }
  }
}
final class PodcastDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    Downloads.shared.backgroundCompletion = completionHandler
    _ = Downloads.shared.session
  }
}
@MainActor final class PodcastStore: ObservableObject {
  @Published var episodes: [Episode] = []
  @Published var current: String?
  @Published var playing = false
  @Published var elapsed: Double = 0
  @Published var duration: Double = 0
  @Published var speed: Float = 1
  @Published var feed = UserDefaults.standard.string(forKey: "feed") ?? ""
  @Published var loading = false
  @Published var downloading: Set<String> = []
  @Published var error: String?
  let player = AVPlayer()
  private var observer: Any?
  private let file = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
      (ProcessInfo.processInfo.environment["PORTFOLIO_UI_TEST"].map { "UITests/" + $0 + "/" } ?? "")
        + "PodcastPocket/library.json")
  private var canSave = true
  init() {
    do {
      episodes = try JSONDecoder().decode([Episode].self, from: Data(contentsOf: file))
    } catch let e as CocoaError where e.code == .fileReadNoSuchFile {
      episodes = [
        Episode(
          id: "preview", title: "Pocket audio preview",
          audio: Bundle.main.url(forResource: "Preview", withExtension: "wav")!,
          summary:
            "A short original tone sequence for checking playback controls. Add an RSS feed for full podcast episodes."
        )
      ]
    } catch {
      canSave = false
      self.error = "Saved library could not be read. The original file is preserved."
    }
    let restored = Downloads.savedDownloads()
    for index in episodes.indices {
      if let name = restored[episodes[index].id],
        FileManager.default.fileExists(
          atPath: Downloads.directory.appendingPathComponent(name).path)
      {
        episodes[index].file = name
      }
    }
    Downloads.shared.onSaved = { [weak self] id, name in
      guard let self else { return }
      if let index = self.episodes.firstIndex(where: { $0.id == id }) {
        self.episodes[index].file = name
        self.save()
      }
      self.downloading.remove(id)
    }
    Downloads.shared.onFailure = { [weak self] id, message in
      self?.downloading.remove(id)
      self?.error = message
    }
    Downloads.shared.session.getAllTasks { tasks in
      DispatchQueue.main.async { self.downloading = Set(tasks.compactMap(\.taskDescription)) }
    }
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    observer = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main
    ) { [weak self] time in
      Task { @MainActor in
        guard let self else { return }
        self.elapsed = max(0, time.seconds.isFinite ? time.seconds : 0)
        self.duration =
          self.player.currentItem?.duration.seconds.isFinite == true
          ? self.player.currentItem!.duration.seconds : 0
        self.playing = self.player.rate != 0
        if let index = self.episodes.firstIndex(where: { $0.id == self.current }) {
          self.episodes[index].position = self.elapsed
        }
        self.nowPlaying()
        if Int(self.elapsed) % 10 == 0 { self.save() }
      }
    }
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.play() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.pause() }
      return .success
    }
    center.skipForwardCommand.preferredIntervals = [30]
    center.skipForwardCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.skip(30) }
      return .success
    }
    center.skipBackwardCommand.preferredIntervals = [15]
    center.skipBackwardCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.skip(-15) }
      return .success
    }
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] note in
      if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
        == AVAudioSession.InterruptionType.began.rawValue
      {
        Task { @MainActor in self?.pause() }
      }
    }
    NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.error = "This episode could not be played. Check the feed or try a download."
      }
    }
  }
  func save() {
    guard canSave else { return }
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(episodes).write(
        to: file, options: [.atomic, .completeFileProtection])
    } catch { self.error = error.localizedDescription }
  }
  func refresh() async {
    guard let url = URL(string: feed), url.scheme == "https", url.host != nil, url.user == nil,
      url.password == nil
    else {
      error = "Enter an HTTPS RSS feed URL."
      return
    }
    loading = true
    defer { loading = false }
    do {
      var req = URLRequest(url: url)
      req.timeoutInterval = 20
      let (data, response) = try await URLSession.shared.data(for: req)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
        data.count < 5_000_000
      else { throw URLError(.badServerResponse) }
      let parsed = try FeedParser().parse(data)
      guard !parsed.isEmpty else {
        throw NSError(domain: "No playable RSS episodes found.", code: 1)
      }
      episodes = mergeEpisodes(parsed, with: episodes)
      save()
      UserDefaults.standard.set(feed, forKey: "feed")
    } catch { self.error = error.localizedDescription }
  }
  func select(_ episode: Episode) {
    pause()
    current = episode.id
    let url = episode.file.map { Downloads.directory.appendingPathComponent($0) } ?? episode.audio
    player.replaceCurrentItem(with: AVPlayerItem(url: url))
    player.seek(to: CMTime(seconds: episode.position, preferredTimescale: 600))
    play()
  }
  func play() {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      player.playImmediately(atRate: speed)
      playing = true
      nowPlaying()
    } catch { self.error = error.localizedDescription }
  }
  func pause() {
    player.pause()
    playing = false
    save()
    nowPlaying()
  }
  func skip(_ seconds: Double) {
    player.seek(
      to: CMTime(
        seconds: max(0, min(duration > 0 ? duration : .greatestFiniteMagnitude, elapsed + seconds)),
        preferredTimescale: 600))
  }
  func nowPlaying() {
    guard let episode = episodes.first(where: { $0.id == current }) else { return }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: episode.title, MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0,
    ]
  }
  func download(_ episode: Episode) {
    guard episode.audio.scheme == "https", !downloading.contains(episode.id) else { return }
    downloading.insert(episode.id)
    Downloads.shared.start(episode)
  }
  func removeDownload(_ episode: Episode) {
    guard let name = episode.file, let index = episodes.firstIndex(where: { $0.id == episode.id })
    else { return }
    do {
      if current == episode.id {
        pause()
        current = nil
      }
      try FileManager.default.removeItem(at: Downloads.directory.appendingPathComponent(name))
      episodes[index].file = nil
      save()
    } catch { self.error = error.localizedDescription }
  }
}
@main struct PodcastApp: App {
  @UIApplicationDelegateAdaptor(PodcastDelegate.self) var delegate
  @StateObject var store = PodcastStore()
  var body: some Scene { WindowGroup { PodcastView().environmentObject(store).tint(.orange) } }
}
struct PodcastView: View {
  @EnvironmentObject var store: PodcastStore
  @State var feeds = false
  @Environment(\.scenePhase) var phase
  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        List {
          Section {
            VStack(alignment: .leading, spacing: 8) {
              Text("Your listening shelf").font(.title2.weight(.semibold))
              Text(
                "Stream an episode, save it for offline listening, and pick up where you left off."
              ).foregroundColor(.secondary)
            }
          }
          Section("Episodes") {
            ForEach(store.episodes) { episode in
              VStack(alignment: .leading, spacing: 12) {
                Button {
                  store.select(episode)
                } label: {
                  HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "waveform").font(.title).frame(width: 50, height: 50)
                      .background(Color.orange.opacity(0.12)).cornerRadius(10)
                    VStack(alignment: .leading, spacing: 6) {
                      Text(episode.title).font(.headline).foregroundColor(.primary)
                      Text(
                        episode.summary.replacingOccurrences(
                          of: "<[^>]+>", with: "", options: .regularExpression)
                      ).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                      if episode.position > 0 {
                        Text(
                          "Resume at \(Int(episode.position/60)):\(String(format:"%02d",Int(episode.position)%60))"
                        ).font(.caption).foregroundColor(.secondary)
                      }
                    }
                  }
                }
                if episode.audio.scheme == "https" {
                  if store.downloading.contains(episode.id) {
                    Label("Downloading…", systemImage: "arrow.down.circle").font(.caption)
                  } else if episode.file != nil {
                    HStack {
                      Label("Available offline", systemImage: "checkmark.circle").font(.caption)
                      Spacer()
                      Button("Remove download", role: .destructive) {
                        store.removeDownload(episode)
                      }.font(.caption)
                    }
                  } else {
                    Button("Download") { store.download(episode) }.font(.caption)
                  }
                }
              }.padding(.vertical, 8)
            }
          }
        }.listStyle(.insetGrouped)
        if let episode = store.episodes.first(where: { $0.id == store.current }) {
          VStack(spacing: 12) {
            Text(episode.title).font(.headline).lineLimit(2)
            if store.duration > 0 {
              Slider(
                value: Binding(
                  get: { min(store.elapsed, store.duration) },
                  set: { store.player.seek(to: CMTime(seconds: $0, preferredTimescale: 600)) }),
                in: 0...store.duration
              ).accessibilityLabel("Playback position")
            }
            HStack(spacing: 30) {
              Button {
                store.skip(-15)
              } label: {
                Image(systemName: "gobackward.15")
              }.accessibilityLabel("Back fifteen seconds")
              Button {
                store.playing ? store.pause() : store.play()
              } label: {
                Image(systemName: store.playing ? "pause.fill" : "play.fill").font(.title)
              }.accessibilityLabel(store.playing ? "Pause" : "Play")
              Button {
                store.skip(30)
              } label: {
                Image(systemName: "goforward.30")
              }.accessibilityLabel("Forward thirty seconds")
              Menu("\(String(format:"%.1f",store.speed))×") {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { rate in
                  Button("\(String(format:"%.2g",rate))×") {
                    store.speed = rate
                    if store.playing { store.play() }
                  }
                }
              }
            }
          }.padding().background(Color(UIColor.secondarySystemBackground))
        }
      }.navigationTitle("Podcast Pocket").toolbar {
        Button {
          feeds = true
        } label: {
          Image(systemName: "plus")
        }.accessibilityLabel("Add RSS feed")
      }
    }
    .navigationViewStyle(.stack).sheet(isPresented: $feeds) {
      NavigationView {
        Form {
          Section("RSS feed") {
            TextField("https://example.com/feed.xml", text: $store.feed)
              .textInputAutocapitalization(.never).disableAutocorrection(true)
            Button(store.loading ? "Loading…" : "Load feed") {
              Task {
                await store.refresh()
                if !store.loading && store.error == nil { feeds = false }
              }
            }.disabled(store.loading)
            Text(
              "Paste a podcast RSS URL with HTTPS audio enclosures. Audio is downloaded directly from its publisher."
            ).font(.footnote)
          }
        }.navigationTitle("Add a feed").toolbar { Button("Done") { feeds = false } }
      }
    }
    .alert(
      "Playback needs attention",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      Button("OK") { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
    .onChange(of: phase) { _ in store.save() }
  }
}
