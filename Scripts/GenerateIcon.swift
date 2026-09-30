import AppKit

let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let names = ["."]
let colors: [(CGFloat, CGFloat, CGFloat)] = [(0.71, 0.3, 0.12)]
func stroke(_ points: [CGPoint], width: CGFloat = 30) {
  let path = NSBezierPath()
  path.lineWidth = width
  path.lineCapStyle = .round
  path.lineJoinStyle = .round
  path.move(to: points[0])
  for point in points.dropFirst() { path.line(to: point) }
  path.stroke()
}
for (index, name) in names.enumerated() {
  let folder = base.appendingPathComponent(name).appendingPathComponent(
    "Resources/Assets.xcassets")
  try FileManager.default.createDirectory(
    at: folder.appendingPathComponent("AppIcon.appiconset"), withIntermediateDirectories: true)
  try FileManager.default.createDirectory(
    at: folder.appendingPathComponent("AccentColor.colorset"), withIntermediateDirectories: true
  )
  let (r, g, b) = colors[index]
  let info: [String: Any] = ["info": ["author": "xcode", "version": 1]]
  try JSONSerialization.data(withJSONObject: info, options: .prettyPrinted).write(
    to: folder.appendingPathComponent("Contents.json"))
  let accent: [String: Any] = [
    "info": ["author": "xcode", "version": 1],
    "colors": [
      [
        "idiom": "universal",
        "color": [
          "color-space": "srgb",
          "components": [
            "red": String(Double(r)), "green": String(Double(g)),
            "blue": String(Double(b)), "alpha": "1.0",
          ],
        ],
      ]
    ],
  ]
  try JSONSerialization.data(withJSONObject: accent, options: .prettyPrinted).write(
    to: folder.appendingPathComponent("AccentColor.colorset/Contents.json"))
  func render(_ pixels: Int, filename: String) throws {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    NSColor(calibratedRed: r, green: g, blue: b, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
    NSColor(calibratedWhite: 0.96, alpha: 1).setStroke()
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    // Original typographic mark; app artwork does not reuse system symbols.
    let font = NSFont.systemFont(ofSize: 310, weight: .semibold)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: NSColor(calibratedWhite: 0.97, alpha: 1),
      .paragraphStyle: paragraph, .kern: -8
    ]
    let mark = NSAttributedString(string: "PP", attributes: attributes)
    mark.draw(in: NSRect(x: 100, y: 335, width: 824, height: 380))
    NSColor(calibratedWhite: 0.97, alpha: 0.7).setFill()
    NSBezierPath(roundedRect: NSRect(x: 390, y: 265, width: 244, height: 20), xRadius: 10, yRadius: 10).fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(
      to: folder.appendingPathComponent("AppIcon.appiconset/" + filename))
  }
  var images: [[String: String]] = []
  do {
    // Explicit slots retain compatibility with deployment targets below iOS 18.
    for (idiom, sizes) in [
      ("iphone", [20.0, 29, 40, 60]), ("ipad", [20.0, 29, 40, 76, 83.5]),
    ] {
      for size in sizes {
        for scale in (idiom == "iphone" ? [2, 3] : (size == 83.5 ? [2] : [1, 2])) {
          let filename = "\(idiom)-\(size)-\(scale).png"
          try render(Int(size * Double(scale)), filename: filename)
          images.append([
            "idiom": idiom, "size": "\(size)x\(size)", "scale": "\(scale)x",
            "filename": filename,
          ])
        }
      }
    }
    try render(1024, filename: "marketing.png")
    images.append([
      "idiom": "ios-marketing", "size": "1024x1024", "scale": "1x",
      "filename": "marketing.png",
    ])
  }
  try JSONSerialization.data(
    withJSONObject: ["info": ["author": "xcode", "version": 1], "images": images],
    options: [.prettyPrinted, .sortedKeys]
  ).write(to: folder.appendingPathComponent("AppIcon.appiconset/Contents.json"))
  print("Rendered \(name)")
}
