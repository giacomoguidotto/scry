import Foundation

// swiftlint:disable nesting
/// Pure data model mapping to the TOML config file structure.
struct ConfigFile: Codable, Equatable {
    var trigger: Trigger
    var appearance: Appearance
    var behavior: Behavior
    var system: System
    var ai: AISection

    // MARK: - Sections

    struct Trigger: Codable, Equatable {
        var forceClick: Bool
        var pressureSensitivity: Double
        var hotkey: String

        enum CodingKeys: String, CodingKey {
            case forceClick = "force_click"
            case pressureSensitivity = "pressure_sensitivity"
            case hotkey
        }

        init(forceClick: Bool = true,
             pressureSensitivity: Double = Constants.Defaults.pressureSensitivity,
             hotkey: String = "globe") {
            self.forceClick = forceClick
            self.pressureSensitivity = pressureSensitivity
            self.hotkey = hotkey
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            forceClick = try c.decodeIfPresent(Bool.self, forKey: .forceClick) ?? true
            pressureSensitivity = try c.decodeIfPresent(Double.self, forKey: .pressureSensitivity)
                ?? Constants.Defaults.pressureSensitivity
            hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "globe"
        }
    }

    struct Appearance: Codable, Equatable {
        var panelOpacity: Double
        var showAnimations: Bool
        var theme: String

        enum CodingKeys: String, CodingKey {
            case panelOpacity = "panel_opacity"
            case showAnimations = "show_animations"
            case theme
        }

        init(panelOpacity: Double = 1.0, showAnimations: Bool = true, theme: String = "system") {
            self.panelOpacity = panelOpacity
            self.showAnimations = showAnimations
            self.theme = theme
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            panelOpacity = try c.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? 1.0
            showAnimations = try c.decodeIfPresent(Bool.self, forKey: .showAnimations) ?? true
            theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        }
    }

    struct Behavior: Codable, Equatable {
        var defaultProvider: String
        var rememberLastProvider: Bool
        var dismissOnLinkClick: Bool
        var openLinksIn: String
        var showShortcutHints: Bool
        var maxQueryLength: Int
        var providers: [String]

        enum CodingKeys: String, CodingKey {
            case defaultProvider = "default_provider"
            case rememberLastProvider = "remember_last_provider"
            case dismissOnLinkClick = "dismiss_on_link_click"
            case openLinksIn = "open_links_in"
            case showShortcutHints = "show_shortcut_hints"
            case maxQueryLength = "max_query_length"
            case providers
        }

        init(defaultProvider: String = Constants.Defaults.defaultProvider,
             rememberLastProvider: Bool = true,
             dismissOnLinkClick: Bool = true,
             openLinksIn: String = LinkTarget.defaultBrowser.rawValue,
             showShortcutHints: Bool = true,
             maxQueryLength: Int = Constants.Timing.maxQueryLength,
             providers: [String] = Constants.Defaults.enabledProviders) {
            self.defaultProvider = defaultProvider
            self.rememberLastProvider = rememberLastProvider
            self.dismissOnLinkClick = dismissOnLinkClick
            self.openLinksIn = openLinksIn
            self.showShortcutHints = showShortcutHints
            self.maxQueryLength = maxQueryLength
            self.providers = providers
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            defaultProvider = try c.decodeIfPresent(String.self, forKey: .defaultProvider)
                ?? Constants.Defaults.defaultProvider
            rememberLastProvider = try c.decodeIfPresent(Bool.self, forKey: .rememberLastProvider) ?? true
            dismissOnLinkClick = try c.decodeIfPresent(Bool.self, forKey: .dismissOnLinkClick) ?? true
            openLinksIn = try c.decodeIfPresent(String.self, forKey: .openLinksIn)
                ?? LinkTarget.defaultBrowser.rawValue
            showShortcutHints = try c.decodeIfPresent(Bool.self, forKey: .showShortcutHints) ?? true
            maxQueryLength = try c.decodeIfPresent(Int.self, forKey: .maxQueryLength)
                ?? Constants.Timing.maxQueryLength
            providers = try c.decodeIfPresent([String].self, forKey: .providers)
                ?? Constants.Defaults.enabledProviders
        }
    }

    struct System: Codable, Equatable {
        var launchAtLogin: Bool
        var showMenuBarIcon: Bool

        enum CodingKeys: String, CodingKey {
            case launchAtLogin = "launch_at_login"
            case showMenuBarIcon = "show_menu_bar_icon"
        }

        init(launchAtLogin: Bool = false, showMenuBarIcon: Bool = true) {
            self.launchAtLogin = launchAtLogin
            self.showMenuBarIcon = showMenuBarIcon
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
            showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        }
    }

    struct AISection: Codable, Equatable {
        var enabled: Bool
        var providerType: String
        var model: String
        var customEndpoint: String
        var screenshotRegionSize: Double
        var screenshotMode: String

        enum CodingKeys: String, CodingKey {
            case enabled
            case providerType = "provider_type"
            case model
            case customEndpoint = "custom_endpoint"
            case screenshotRegionSize = "screenshot_region_size"
            case screenshotMode = "screenshot_mode"
        }

        init(enabled: Bool = false,
             providerType: String = AIProviderType.claude.rawValue,
             model: String = Constants.AIConfig.defaultClaudeModel,
             customEndpoint: String = "",
             screenshotRegionSize: Double = Double(Constants.Screenshot.defaultRegionSize),
             screenshotMode: String = ScreenshotMode.window.rawValue) {
            self.enabled = enabled
            self.providerType = providerType
            self.model = model
            self.customEndpoint = customEndpoint
            self.screenshotRegionSize = screenshotRegionSize
            self.screenshotMode = screenshotMode
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            providerType = try c.decodeIfPresent(String.self, forKey: .providerType)
                ?? AIProviderType.claude.rawValue
            model = try c.decodeIfPresent(String.self, forKey: .model)
                ?? Constants.AIConfig.defaultClaudeModel
            customEndpoint = try c.decodeIfPresent(String.self, forKey: .customEndpoint) ?? ""
            screenshotRegionSize = try c.decodeIfPresent(Double.self, forKey: .screenshotRegionSize)
                ?? Double(Constants.Screenshot.defaultRegionSize)
            screenshotMode = try c.decodeIfPresent(String.self, forKey: .screenshotMode)
                ?? ScreenshotMode.window.rawValue
        }
    }

    // MARK: - Top-level Codable

    enum CodingKeys: String, CodingKey {
        case trigger, appearance, behavior, system, ai
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trigger = try c.decodeIfPresent(Trigger.self, forKey: .trigger) ?? Trigger()
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? Appearance()
        behavior = try c.decodeIfPresent(Behavior.self, forKey: .behavior) ?? Behavior()
        system = try c.decodeIfPresent(System.self, forKey: .system) ?? System()
        ai = try c.decodeIfPresent(AISection.self, forKey: .ai) ?? AISection()
    }

    // MARK: - Factories

    static func makeDefault() -> ConfigFile {
        ConfigFile(
            trigger: Trigger(),
            appearance: Appearance(),
            behavior: Behavior(),
            system: System(),
            ai: AISection()
        )
    }

    init(trigger: Trigger, appearance: Appearance, behavior: Behavior, system: System, ai: AISection) {
        self.trigger = trigger
        self.appearance = appearance
        self.behavior = behavior
        self.system = system
        self.ai = ai
    }

    init(from settings: AppSettings) {
        trigger = Trigger(
            forceClick: settings.forceClick,
            pressureSensitivity: settings.pressureSensitivity,
            hotkey: settings.hotkey.configString
        )
        appearance = Appearance(
            panelOpacity: settings.panelOpacity,
            showAnimations: settings.showAnimations,
            theme: settings.theme.rawValue
        )
        behavior = Behavior(
            defaultProvider: settings.defaultProvider,
            rememberLastProvider: settings.rememberLastProvider,
            dismissOnLinkClick: settings.dismissOnLinkClick,
            openLinksIn: settings.openLinksIn.rawValue,
            showShortcutHints: settings.showShortcutHints,
            maxQueryLength: settings.maxQueryLength,
            providers: settings.providerOrder
        )
        system = System(
            launchAtLogin: settings.launchAtLogin,
            showMenuBarIcon: settings.showMenuBarIcon
        )
        ai = AISection(
            enabled: settings.aiEnabled,
            providerType: settings.aiProviderType.rawValue,
            model: settings.aiModel,
            customEndpoint: settings.aiCustomEndpoint,
            screenshotRegionSize: Double(settings.screenshotRegionSize),
            screenshotMode: settings.screenshotMode.rawValue
        )
    }

    func apply(to settings: AppSettings) {
        settings.forceClick = trigger.forceClick
        settings.pressureSensitivity = trigger.pressureSensitivity
        settings.hotkey = Hotkey(configString: trigger.hotkey)

        settings.panelOpacity = appearance.panelOpacity
        settings.showAnimations = appearance.showAnimations
        if let val = Theme(rawValue: appearance.theme) { settings.theme = val }

        settings.defaultProvider = behavior.defaultProvider
        settings.rememberLastProvider = behavior.rememberLastProvider
        settings.dismissOnLinkClick = behavior.dismissOnLinkClick
        if let val = LinkTarget(rawValue: behavior.openLinksIn) { settings.openLinksIn = val }
        settings.showShortcutHints = behavior.showShortcutHints
        settings.maxQueryLength = behavior.maxQueryLength
        settings.providerOrder = behavior.providers
        settings.enabledProviders = behavior.providers

        settings.launchAtLogin = system.launchAtLogin
        settings.showMenuBarIcon = system.showMenuBarIcon

        settings.aiEnabled = ai.enabled
        if let val = AIProviderType(rawValue: ai.providerType) { settings.aiProviderType = val }
        settings.aiModel = ai.model
        settings.aiCustomEndpoint = ai.customEndpoint
        settings.screenshotRegionSize = CGFloat(ai.screenshotRegionSize)
        if let mode = ScreenshotMode(rawValue: ai.screenshotMode) {
            settings.screenshotMode = mode
        }
    }

    // MARK: - TOML Output

    func toAnnotatedTOML() -> String {
        let providersStr = behavior.providers.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        [trigger]
        # Trigger search by force-clicking (deep press) on a trackpad
        force_click = \(trigger.forceClick)
        # Force-click threshold (0.0\u{2013}1.0, higher = harder press needed)
        pressure_sensitivity = \(Self.fmtFloat(trigger.pressureSensitivity))
        # Keyboard trigger. Formats:
        #   Single modifier tap: "globe", "cmd", "opt", "ctrl", "shift"
        #   Double-tap modifier: "cmd cmd", "shift shift", etc.
        #   Key combination: "cmd+shift+g", "ctrl+opt+k", etc.
        #   Set to "" to disable
        hotkey = "\(trigger.hotkey)"

        [appearance]
        panel_opacity = \(Self.fmtFloat(appearance.panelOpacity))
        show_animations = \(appearance.showAnimations)
        # Options: system, light, dark
        theme = "\(appearance.theme)"

        [behavior]
        # Provider used when opening a new search panel
        # Options: google, duckduckgo, wikipedia, ai
        default_provider = "\(behavior.defaultProvider)"
        # Re-open with the last provider you used instead of the default
        remember_last_provider = \(behavior.rememberLastProvider)
        # Close the panel when you click a link in the results
        dismiss_on_link_click = \(behavior.dismissOnLinkClick)
        # Options: defaultBrowser, safari, chrome
        open_links_in = "\(behavior.openLinksIn)"
        # Show keyboard shortcut hints in the search panel
        show_shortcut_hints = \(behavior.showShortcutHints)
        max_query_length = \(behavior.maxQueryLength)
        # Only listed providers are enabled, in this order
        # Options: google, duckduckgo, wikipedia, ai
        providers = [\(providersStr)]

        [system]
        launch_at_login = \(system.launchAtLogin)
        show_menu_bar_icon = \(system.showMenuBarIcon)

        [ai]
        enabled = \(ai.enabled)
        # Options: claude, openai, ollama, custom
        provider_type = "\(ai.providerType)"
        model = "\(ai.model)"
        # Custom OpenAI-compatible endpoint URL (only used when provider_type = "custom")
        custom_endpoint = "\(ai.customEndpoint)"
        # Size in px of the screenshot region captured around the cursor for AI analysis
        screenshot_region_size = \(Self.fmtFloat(ai.screenshotRegionSize))
        # Options: region, window, screen
        screenshot_mode = "\(ai.screenshotMode)"
        """
    }

    private static func fmtFloat(_ value: Double) -> String {
        if value == value.rounded(.towardZero) && abs(value) < 1_000_000 {
            return String(format: "%.1f", value)
        }
        var s = String(format: "%.2f", value)
        while s.hasSuffix("0") && !s.hasSuffix(".0") { s = String(s.dropLast()) }
        return s
    }
}
// swiftlint:enable nesting
