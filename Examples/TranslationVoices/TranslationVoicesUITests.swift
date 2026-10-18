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

    /// Supply only an owned test room's scoped handoff. This test never creates rooms.
    func testLiveCatalogueInOwnedRoom() throws {
        let environment = ProcessInfo.processInfo.environment
        let keys = ["MEDIASFU_TEST_DISPLAY_NAME", "MEDIASFU_TEST_ROOM_NAME", "MEDIASFU_TEST_ROOM_TOKEN", "MEDIASFU_TEST_ROOM_LINK"]
        guard keys.allSatisfy({ !(environment[$0] ?? "").isEmpty }) else {
            throw XCTSkip("An owned room handoff is required for live catalogue validation.")
        }
        let app = XCUIApplication()
        app.launch()
        defer {
            // Request the room's normal exit flow before terminating the test app.
            if app.buttons["Done"].firstMatch.isHittable { app.buttons["Done"].firstMatch.tap() }
            if app.buttons["Room"].firstMatch.isHittable {
                app.buttons["Room"].firstMatch.tap()
                if app.buttons["Leave room"].waitForExistence(timeout: 2) { app.buttons["Leave room"].tap() }
                let end = app.buttons.matching(NSPredicate(format: "label IN %@", ["End for everyone", "Exit"])).firstMatch
                if end.waitForExistence(timeout: 5) { end.tap() }
            }
            app.terminate()
        }
        let fields = ["Display name", "Room name", "Room-scoped token", "Room media link"]
        for (field, key) in zip(fields, keys) {
            let element = field == "Room-scoped token" ? app.secureTextFields[field] : app.textFields[field]
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            element.tap()
            element.typeText(environment[key]!)
        }
        app.buttons["Join room"].tap()
        XCTAssertTrue(app.buttons["Translation voice"].waitForExistence(timeout: 30))
        app.buttons["Translation voice"].tap()
        let voices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "translationVoice:"))
        let voice = voices.firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout: 45), "The room must return a selectable catalogue for French.")
        guard voice.exists else { return }
        voice.tap()
        XCTAssertEqual(voice.value as? String, "Selected")
        let language = app.textFields["Output language code"]
        language.tap()
        language.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "de")
        XCTAssertFalse(app.buttons["Apply voice"].isEnabled, "Changing output language must clear the stock selection.")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Live catalogue context invalidation"
        image.lifetime = .keepAlways
        add(image)
    }

}
