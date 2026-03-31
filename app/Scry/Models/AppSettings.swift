import AppKit
import Combine
import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
  static let shared = AppSettings()

  private let defaults = UserDefaults.standard
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Trigger

  @Published var forceClick: Bool = true {
    didSet { defaults.set(forceClick, forKey: Keys.forceClick) }
  }

  @Published var hotkey: Hotkey = .modifierTap(.globe) {
    didSet { defaults.set(hotkey.configString, forKey: Keys.hotkey) }
  }

  @Published var pressureSensitivity: Double = Constants.Defaults.pressureSensitivity {
    didSet { defaults.set(pressureSensitivity, forKey: Keys.pressureSensitivity) }
  }

  // MARK: - Appearance

  @Published var panelWidth: CGFloat = Constants.Panel.defaultWidth {
    didSet { defaults.set(panelWidth, forKey: Keys.panelWidth) }
  }

  @Published var panelHeight: CGFloat = Constants.Panel.defaultHeight {
    didSet { defaults.set(panelHeight, forKey: Keys.panelHeight) }
  }

  @Published var panelOpacity: Double = 1.0 {
    didSet { defaults.set(panelOpacity, forKey: Keys.panelOpacity) }
  }

  @Published var cornerRadius: CGFloat = Constants.Panel.defaultCornerRadius {
    didSet { defaults.set(cornerRadius, forKey: Keys.cornerRadius) }
  }

  @Published var showAnimations: Bool = true {
    didSet { defaults.set(showAnimations, forKey: Keys.showAnimations) }
  }

  @Published var theme: Theme = .system {
    didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
  }

  // MARK: - Behavior

  @Published var defaultProvider: String = Constants.Defaults.defaultProvider {
    didSet { defaults.set(defaultProvider, forKey: Keys.defaultProvider) }
  }

  @Published var rememberLastProvider: Bool = true {
    didSet { defaults.set(rememberLastProvider, forKey: Keys.rememberLastProvider) }
  }

  @Published var lastUsedProvider: String = Constants.Defaults.defaultProvider {
    didSet { defaults.set(lastUsedProvider, forKey: Keys.lastUsedProvider) }
  }

  @Published var dismissOnLinkClick: Bool = true {
    didSet { defaults.set(dismissOnLinkClick, forKey: Keys.dismissOnLinkClick) }
  }

  @Published var openLinksIn: LinkTarget = .defaultBrowser {
    didSet { defaults.set(openLinksIn.rawValue, forKey: Keys.openLinksIn) }
  }

  @Published var showShortcutHints: Bool = true {
    didSet { defaults.set(showShortcutHints, forKey: Keys.showShortcutHints) }
  }

  @Published var maxQueryLength: Int = Constants.Timing.maxQueryLength {
    didSet { defaults.set(maxQueryLength, forKey: Keys.maxQueryLength) }
  }

  // MARK: - Providers

  @Published var enabledProviders: [String] = Constants.Defaults.enabledProviders {
    didSet { defaults.set(enabledProviders, forKey: Keys.enabledProviders) }
  }

  @Published var providerOrder: [String] = Constants.Defaults.enabledProviders {
    didSet { defaults.set(providerOrder, forKey: Keys.providerOrder) }
  }

  // MARK: - System

  @Published var launchAtLogin: Bool = false {
    didSet {
      defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
      updateLaunchAtLogin()
    }
  }

  @Published var showMenuBarIcon: Bool = true {
    didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
  }

  @Published var hasCompletedOnboarding: Bool = false {
    didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
  }

  // MARK: - AI

  @Published var aiEnabled: Bool = false {
    didSet { defaults.set(aiEnabled, forKey: Keys.aiEnabled) }
  }

  @Published var aiProviderType: AIProviderType = .claude {
    didSet { defaults.set(aiProviderType.rawValue, forKey: Keys.aiProviderType) }
  }

  @Published var aiAPIKey: String = "" {
    didSet { defaults.set(aiAPIKey, forKey: Keys.aiAPIKey) }
  }

  @Published var aiModel: String = Constants.AIConfig.defaultClaudeModel {
    didSet { defaults.set(aiModel, forKey: Keys.aiModel) }
  }

  @Published var aiCustomEndpoint: String = "" {
    didSet { defaults.set(aiCustomEndpoint, forKey: Keys.aiCustomEndpoint) }
  }

  @Published var screenshotRegionSize: CGFloat = Constants.Screenshot.defaultRegionSize {
    didSet { defaults.set(screenshotRegionSize, forKey: Keys.screenshotRegionSize) }
  }

  @Published var screenshotMode: ScreenshotMode = .window {
    didSet { defaults.set(screenshotMode.rawValue, forKey: Keys.screenshotMode) }
  }

  // MARK: - Init

  private typealias Keys = Constants.UserDefaultsKeys

  private init() {
    load()
  }

  private func load() {
    let d = defaults
    loadTriggerSettings(from: d)
    loadAppearanceSettings(from: d)
    loadBehaviorSettings(from: d)
    loadSystemSettings(from: d)
    loadAISettings(from: d)
  }

  private func loadTriggerSettings(from d: UserDefaults) {
    // forceClick (renamed from forceClickEnabled)
    if d.object(forKey: Keys.forceClick) != nil {
      forceClick = d.bool(forKey: Keys.forceClick)
    } else if d.object(forKey: Keys.forceClickEnabled) != nil {
      forceClick = d.bool(forKey: Keys.forceClickEnabled)
    } else if let raw = d.string(forKey: Keys.triggerMethod) {
      forceClick = (raw == "forceClick")
    }

    // hotkey (replaces doubleTapEnabled + doubleTapModifier + hotKeyEnabled + hotKey)
    if let raw = d.string(forKey: Keys.hotkey) {
      hotkey = Hotkey(configString: raw)
    } else {
      hotkey = migrateHotkeyFromLegacyKeys(d)
    }

    if d.object(forKey: Keys.pressureSensitivity) != nil {
      pressureSensitivity = d.double(forKey: Keys.pressureSensitivity)
    }
  }

  private func migrateHotkeyFromLegacyKeys(_ d: UserDefaults) -> Hotkey {
    let dtEnabled = d.object(forKey: Keys.doubleTapEnabled) != nil
      ? d.bool(forKey: Keys.doubleTapEnabled) : true
    let hkEnabled = d.object(forKey: Keys.hotKeyEnabled) != nil
      ? d.bool(forKey: Keys.hotKeyEnabled) : false

    if dtEnabled {
      let modifier: DoubleTapModifier
      if let raw = d.string(forKey: Keys.doubleTapModifier),
         let val = DoubleTapModifier(rawValue: raw) {
        modifier = val
      } else {
        modifier = .globe
      }
      // Globe uses auto single/double; other modifiers default to double-tap
      return modifier == .globe ? .modifierTap(.globe) : .modifierDoubleTap(modifier)
    } else if hkEnabled {
      let storedKeyCode = d.object(forKey: Keys.hotKeyKeyCode) as? UInt32
      let storedModifiers = d.object(forKey: Keys.hotKeyModifiers) as? UInt32
      if let kc = storedKeyCode, let mod = storedModifiers {
        return .keyCombo(KeyCombo(keyCode: kc, modifiers: NSEvent.ModifierFlags.fromCarbon(mod)))
      }
    }
    return .modifierTap(.globe)
  }

  private func loadAppearanceSettings(from d: UserDefaults) {
    if d.object(forKey: Keys.panelWidth) != nil {
      panelWidth = d.double(forKey: Keys.panelWidth)
    }
    if d.object(forKey: Keys.panelHeight) != nil {
      panelHeight = d.double(forKey: Keys.panelHeight)
    }
    if d.object(forKey: Keys.panelOpacity) != nil {
      panelOpacity = d.double(forKey: Keys.panelOpacity)
    }
    if d.object(forKey: Keys.cornerRadius) != nil {
      cornerRadius = d.double(forKey: Keys.cornerRadius)
    }
    if d.object(forKey: Keys.showAnimations) != nil {
      showAnimations = d.bool(forKey: Keys.showAnimations)
    }
    if let raw = d.string(forKey: Keys.theme), let val = Theme(rawValue: raw) {
      theme = val
    }
  }

  private func loadBehaviorSettings(from d: UserDefaults) {
    if let val = d.string(forKey: Keys.defaultProvider) {
      defaultProvider = val
    }
    if d.object(forKey: Keys.rememberLastProvider) != nil {
      rememberLastProvider = d.bool(forKey: Keys.rememberLastProvider)
    }
    if let val = d.string(forKey: Keys.lastUsedProvider) {
      lastUsedProvider = val
    }
    if d.object(forKey: Keys.dismissOnLinkClick) != nil {
      dismissOnLinkClick = d.bool(forKey: Keys.dismissOnLinkClick)
    }
    if let raw = d.string(forKey: Keys.openLinksIn), let val = LinkTarget(rawValue: raw) {
      openLinksIn = val
    }
    if d.object(forKey: Keys.showShortcutHints) != nil {
      showShortcutHints = d.bool(forKey: Keys.showShortcutHints)
    }
    if d.object(forKey: Keys.maxQueryLength) != nil {
      maxQueryLength = d.integer(forKey: Keys.maxQueryLength)
    }
    if let val = d.array(forKey: Keys.enabledProviders) as? [String] {
      enabledProviders = val
    }
    if let val = d.array(forKey: Keys.providerOrder) as? [String] {
      providerOrder = val
    }
  }

  private func loadSystemSettings(from d: UserDefaults) {
    if d.object(forKey: Keys.launchAtLogin) != nil {
      launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
    }
    if d.object(forKey: Keys.showMenuBarIcon) != nil {
      showMenuBarIcon = d.bool(forKey: Keys.showMenuBarIcon)
    }
    if d.object(forKey: Keys.hasCompletedOnboarding) != nil {
      hasCompletedOnboarding = d.bool(forKey: Keys.hasCompletedOnboarding)
    }
  }

  private func loadAISettings(from d: UserDefaults) {
    if d.object(forKey: Keys.aiEnabled) != nil {
      aiEnabled = d.bool(forKey: Keys.aiEnabled)
    }
    if let raw = d.string(forKey: Keys.aiProviderType), let val = AIProviderType(rawValue: raw) {
      aiProviderType = val
    }
    if let val = d.string(forKey: Keys.aiAPIKey) { aiAPIKey = val }
    if let val = d.string(forKey: Keys.aiModel), !val.isEmpty { aiModel = val }
    if let val = d.string(forKey: Keys.aiCustomEndpoint) { aiCustomEndpoint = val }
    if d.object(forKey: Keys.screenshotRegionSize) != nil {
      screenshotRegionSize = d.double(forKey: Keys.screenshotRegionSize)
    }
    if let raw = d.string(forKey: Keys.screenshotMode),
       let val = ScreenshotMode(rawValue: raw) {
      screenshotMode = val
    }
  }

  // MARK: - ConfigFile Bridge

  func apply(_ config: ConfigFile) {
    config.apply(to: self)
  }

  func toConfigFile() -> ConfigFile {
    ConfigFile(from: self)
  }

  /// The effective provider ID to use when opening a new panel.
  var effectiveProvider: String {
    if rememberLastProvider {
      return lastUsedProvider
    }
    return defaultProvider
  }

  // MARK: - Launch at Login

  private func updateLaunchAtLogin() {
    let service = SMAppService.mainApp
    do {
      if launchAtLogin {
        try service.register()
      } else {
        try service.unregister()
      }
    } catch {
      DebugLogStore.shared.log(
        "Settings", "Launch at login failed: \(error.localizedDescription)", level: .error)
    }
  }
}
