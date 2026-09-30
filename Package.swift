// swift-tools-version: 5.7
import PackageDescription
let package = Package(name: "PodcastCore", platforms: [.iOS(.v15), .macOS(.v12)], products: [.library(name: "PodcastCore", targets: ["PodcastCore"])], targets: [.target(name: "PodcastCore", path: "Sources/Core"), .testTarget(name: "PodcastCoreTests", dependencies: ["PodcastCore"], path: "Tests/Core")])
