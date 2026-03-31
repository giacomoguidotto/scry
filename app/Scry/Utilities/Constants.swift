import Foundation
import AppKit

enum Constants {
    static let appName = "Scry"
    static let bundleIdentifier = "com.giacomo.Scry"

    enum Panel {
        static let defaultWidth: CGFloat = 520
        static let defaultHeight: CGFloat = 580
        static let defaultCornerRadius: CGFloat = 20
        static let edgeMargin: CGFloat = 12
        static let searchBarHeight: CGFloat = 52
        static let tabBarHeight: CGFloat = 38
        static let minWidth: CGFloat = 360
        static let minHeight: CGFloat = 300
        static let maxWidth: CGFloat = 900
        static let maxHeight: CGFloat = 800
    }

    enum Timing {
        static let debounceCooldown: TimeInterval = 0.3
        static let healthCheckInterval: TimeInterval = 5.0
        static let maxQueryLength = 200
    }

    enum Screenshot {
        static let defaultRegionSize: CGFloat = 600
        static let minRegionSize: CGFloat = 150
        static let maxRegionSize: CGFloat = 1200
        static let maxImageEdge: Int = 2000
    }

    enum AIConfig {
        static let defaultClaudeModel = "claude-sonnet-4-6"
        static let defaultOpenAIModel = "gpt-4o"
        static let defaultOllamaModel = "llama3.2"
        static let claudeEndpoint = "https://api.anthropic.com/v1/messages"
        static let openAIEndpoint = "https://api.openai.com/v1/chat/completions"
        static let ollamaEndpoint = "http://localhost:11434/v1/chat/completions"
        static let ollamaBaseURL = "http://localhost:11434"
        static let maxTokens = 1024
    }

    enum Defaults {
        static let pressureSensitivity: Double = 0.8
        static let defaultProvider = "google"
        static let enabledProviders = ["google", "duckduckgo", "wikipedia"]
    }

    enum UserDefaultsKeys {
        static let forceClick = "forceClick"
        static let hotkey = "hotkey"
        static let pressureSensitivity = "pressureSensitivity"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let panelOpacity = "panelOpacity"
        static let cornerRadius = "cornerRadius"
        static let showAnimations = "showAnimations"
        static let theme = "theme"
        static let defaultProvider = "defaultProvider"
        static let rememberLastProvider = "rememberLastProvider"
        static let lastUsedProvider = "lastUsedProvider"
        static let dismissOnLinkClick = "dismissOnLinkClick"
        static let openLinksIn = "openLinksIn"
        static let showShortcutHints = "showShortcutHints"
        static let maxQueryLength = "maxQueryLength"
        static let enabledProviders = "enabledProviders"
        static let providerOrder = "providerOrder"
        static let launchAtLogin = "launchAtLogin"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let aiEnabled = "aiEnabled"
        static let aiProviderType = "aiProviderType"
        static let aiAPIKey = "aiAPIKey"
        static let aiModel = "aiModel"
        static let aiCustomEndpoint = "aiCustomEndpoint"
        static let screenshotRegionSize = "screenshotRegionSize"
        static let screenshotMode = "screenshotMode"

        // Legacy keys for migration only
        static let triggerMethod = "triggerMethod"
        static let forceClickEnabled = "forceClickEnabled"
        static let doubleTapEnabled = "doubleTapEnabled"
        static let doubleTapModifier = "doubleTapModifier"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
    }
}
