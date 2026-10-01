import XCTest
@testable import Scry

final class AppSettingsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset the isolated test settings without touching the real app's defaults.
        let settings = AppSettings.shared
        settings.forceClick = true
        settings.hotkey = .modifierTap(.globe)
        settings.pressureSensitivity = Constants.Defaults.pressureSensitivity
        settings.panelWidth = Constants.Panel.defaultWidth
        settings.panelHeight = Constants.Panel.defaultHeight
        settings.showAnimations = true
        settings.theme = .system
        settings.defaultProvider = "google"
        settings.enabledProviders = Constants.Defaults.enabledProviders
        settings.providerOrder = Constants.Defaults.enabledProviders
    }

    func testDefaultValues() {
        let settings = AppSettings.shared
        XCTAssertTrue(settings.forceClick)
        XCTAssertEqual(settings.hotkey, .modifierTap(.globe))
        XCTAssertEqual(settings.pressureSensitivity, Constants.Defaults.pressureSensitivity)
        XCTAssertEqual(settings.panelWidth, Constants.Panel.defaultWidth)
        XCTAssertEqual(settings.panelHeight, Constants.Panel.defaultHeight)
        XCTAssertTrue(settings.showAnimations)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.defaultProvider, "google")
    }

    func testEnabledProvidersDefault() {
        let settings = AppSettings.shared
        XCTAssertEqual(settings.enabledProviders, ["google", "duckduckgo", "wikipedia"])
        XCTAssertEqual(settings.providerOrder, ["google", "duckduckgo", "wikipedia"])
    }

    func testEffectiveProvider_defaultsToGoogle() {
        let settings = AppSettings.shared
        settings.rememberLastProvider = false
        XCTAssertEqual(settings.effectiveProvider, "google")
    }

    func testEffectiveProvider_remembersLastUsed() {
        let settings = AppSettings.shared
        settings.rememberLastProvider = true
        settings.lastUsedProvider = "wikipedia"
        XCTAssertEqual(settings.effectiveProvider, "wikipedia")
    }

}
