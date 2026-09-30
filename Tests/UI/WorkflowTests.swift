import XCTest

final class WorkflowTests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  override func tearDownWithError() throws { XCUIApplication().terminate() }

  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["PORTFOLIO_UI_TEST"] = UUID().uuidString
    app.launch()
    return app
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func testPreviewPlaybackAndInvalidFeed() {
    let app = launch()
    XCTAssertTrue(app.staticTexts["Pocket audio preview"].waitForExistence(timeout: 10))
    capture(app, "library")
    app.staticTexts["Pocket audio preview"].tap()
    XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
    app.buttons["Pause"].tap()
    XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    app.buttons["Add RSS feed"].tap()
    let field = app.textFields["https://example.com/feed.xml"]
    field.tap()
    field.typeText("http://example.com/feed")
    app.buttons["Load feed"].tap()
    XCTAssertTrue(app.alerts["Playback needs attention"].waitForExistence(timeout: 5))
  }
}
