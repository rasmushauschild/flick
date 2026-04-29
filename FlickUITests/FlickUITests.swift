import XCTest

final class FlickUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        // Best-effort termination; an LSUIElement app sometimes resists terminate().
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
        }
    }

    /// Sanity check: the editor exists and accepts typed input.
    func testEditorAcceptsInput() throws {
        let editor = app.textViews["flickEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Editor should appear after launch")

        editor.click()
        // Move cursor to the very start so we type into the initial empty paragraph
        // rather than appending below it.
        editor.typeKey(.upArrow, modifierFlags: [.command])
        editor.typeText("hello world")

        // The editor's value reflects the typed text. The buffer adds a trailing newline.
        guard let value = editor.value as? String else {
            XCTFail("Editor value is not a string")
            return
        }
        XCTAssertTrue(
            value.hasPrefix("hello world"),
            "Editor should contain typed text — got: \(value.debugDescription)"
        )
    }

    /// Reproduce the original bug: pressing Enter at the end of a todo line should
    /// produce a new editable line (with its own checkbox), not "swallow" the keystroke.
    func testEnterAtEndOfTodoCreatesNewParagraph() throws {
        let editor = app.textViews["flickEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Editor should appear after launch")

        editor.click()
        // Move cursor to the very start so we type into the initial empty paragraph
        // rather than appending below it.
        editor.typeKey(.upArrow, modifierFlags: [.command])
        editor.typeText("buy milk")

        // Convert the current paragraph to a todo by clicking the checkbox button.
        let todoButton = app.buttons["convertButton.todo"]
        XCTAssertTrue(todoButton.waitForExistence(timeout: 2), "Checkbox button should exist")
        todoButton.click()

        // Press Return to create a new line below.
        editor.click()
        editor.typeKey(.return, modifierFlags: [])

        // We expect the editor to now contain "buy milk" followed by at least two
        // newlines: the terminator of "buy milk", the new empty line, and (because
        // of the trailing buffer) one more empty line.
        guard let value = editor.value as? String else {
            XCTFail("Editor value is not a string")
            return
        }
        XCTAssertTrue(
            value.hasPrefix("buy milk\n"),
            "Editor should contain todo text — got: \(value.debugDescription)"
        )
        let newlineCount = value.filter { $0 == "\n" }.count
        XCTAssertGreaterThanOrEqual(
            newlineCount, 2,
            "Editor should have at least 2 newlines (new line + buffer) — got \(newlineCount)"
        )

        // Capture a screenshot so we can visually verify the checkbox appeared on the new line.
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "After Enter on todo"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
