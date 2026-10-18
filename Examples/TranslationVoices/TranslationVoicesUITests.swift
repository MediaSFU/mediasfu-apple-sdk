import XCTest

final class TranslationVoicesUITests: XCTestCase {
    func testLinkedRuntimeLoadsTheRoomHandoffForm() {
        let app = XCUIApplication()
        app.launch()
        let status = app.staticTexts["runtimeLinkStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertEqual(status.label, "MediaSFU runtime linked")
        XCTAssertEqual(app.staticTexts["nativeMediaStatus"].label, "Native media binding active")
        XCTAssertTrue(app.textFields["Room name"].exists)
        XCTAssertFalse(app.buttons["Join room"].isEnabled)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Linked runtime onboarding"
        image.lifetime = .keepAlways
        add(image)
    }
}
