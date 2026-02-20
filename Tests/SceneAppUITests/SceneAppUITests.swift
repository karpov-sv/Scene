import XCTest

final class SceneAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launchEnvironment["SCENE_UI_TEST_MODE"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func tabPicker(in app: XCUIApplication) -> XCUIElement {
        let picker = app.radioGroups["workspace.tabPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8), "Workspace tab picker not found")
        return picker
    }

    @MainActor
    private func tabButton(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let picker = tabPicker(in: app)
        let button = picker.radioButtons[name]
        XCTAssertTrue(button.exists, "Workspace tab '\(name)' not found")
        return button
    }

    @MainActor
    private func selectWorkspaceTab(_ name: String, in app: XCUIApplication) {
        tabButton(name, in: app).click()
    }

    @MainActor
    private func assertTabSelected(_ name: String, in app: XCUIApplication) {
        let value = tabButton(name, in: app).value
        if let number = value as? NSNumber {
            XCTAssertEqual(number.intValue, 1, "Workspace tab '\(name)' is not selected")
            return
        }
        if let string = value as? String {
            let normalized = string.lowercased()
            XCTAssertTrue(
                normalized == "1" || normalized == "selected" || normalized == "on",
                "Workspace tab '\(name)' is not selected"
            )
            return
        }
        XCTFail("Unable to determine selected state for workspace tab '\(name)'")
    }

    @MainActor
    func testLaunchesIntoWorkspaceAndCanSwitchTabs() throws {
        let app = launchApp()
        _ = tabPicker(in: app)
        selectWorkspaceTab("Workshop", in: app)
        assertTabSelected("Workshop", in: app)

        selectWorkspaceTab("Writing", in: app)
        assertTabSelected("Writing", in: app)
    }

    @MainActor
    func testClearMessagesButtonShowsConfirmationDialog() throws {
        let app = launchApp()
        selectWorkspaceTab("Workshop", in: app)
        assertTabSelected("Workshop", in: app)

        let clearButton = app.buttons["Clear Messages"].firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5), "Clear Messages button not found")
        clearButton.click()

        let confirmationSheet = app.sheets.firstMatch
        XCTAssertTrue(
            confirmationSheet.waitForExistence(timeout: 3),
            "Clear confirmation sheet did not appear"
        )

        let cancelButton = confirmationSheet.buttons["Cancel"].firstMatch
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 2),
            "Cancel button not found in clear confirmation dialog"
        )
        cancelButton.click()
    }
}
