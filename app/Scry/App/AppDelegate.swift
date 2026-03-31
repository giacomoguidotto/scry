import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
  static private(set) weak var shared: AppDelegate?

  private let settings = AppSettings.shared
  private let permissions = PermissionsService.shared
  private var onboardingController = OnboardingWindowController()
  private var preferencesController: PreferencesWindowController?
  private var eventTapService: EventTapService?
  private var textExtractorService: TextExtractorService?
  private var hotKeyService: HotKeyService?
  private var doubleTapService: DoubleTapService?
  private var searchPanelController: SearchPanelController?
  private var cancellables = Set<AnyCancellable>()
  private var lastPermissionToast: Date = .distantPast
  private let permissionToastCooldown: TimeInterval = 60

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppDelegate.shared = self

    // Hosted test bundle: the app is launched as test host, skip all
    // services to avoid blocking (CGEvent taps, Sparkle, windows, etc.)
    guard ProcessInfo.processInfo.environment["SCRY_TESTING"] != "1" else { return }

    // Load XDG config (or migrate from UserDefaults on first run)
    ConfigFileService.shared.loadAndMigrate()

    // Start Sparkle updater
    _ = UpdaterService.shared

    if settings.hasCompletedOnboarding {
      permissions.checkAllIncludingInputMonitoring()
      setupServices()
      observeSettings()
    } else {
      // Defer services until onboarding reaches step 4 (permissions granted)
      observeSettings()
      onboardingController.onServicesNeeded = { [weak self] in
        self?.permissions.checkAllIncludingInputMonitoring()
        self?.setupServices()
      }
      onboardingController.show()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    eventTapService?.stop()
    hotKeyService?.unregister()
    doubleTapService?.stop()
    searchPanelController?.dismiss()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // MARK: - Public

  func showPreferences() {
    if preferencesController == nil {
      preferencesController = PreferencesWindowController()
    }
    preferencesController?.show()
  }

  func performSearch(at point: NSPoint?) {
    // If onboarding step 4 is active, dismiss it and proceed with search
    if !settings.hasCompletedOnboarding && onboardingController.isOnStepFour {
      onboardingController.dismissForSearch()
    }

    let debugLog = DebugLogStore.shared
    debugLog.log("Search", "performSearch called", level: .debug)

    let position = point ?? NSEvent.mouseLocation

    // Check accessibility permission — open panel with grant banner if missing
    permissions.checkAll()
    if !permissions.accessibilityGranted {
      debugLog.log("Search", "Accessibility not granted — showing grant panel", level: .warning)
      RippleOverlay.show(at: position, color: ScryTheme.Colors.error)
      if searchPanelController == nil {
        searchPanelController = SearchPanelController()
      }
      searchPanelController?.showAccessibilityPrompt(at: position)
      return
    }

    // Capture frontmost app NOW, before any UI work changes focus
    let frontApp = NSWorkspace.shared.frontmostApplication

    // Instant visual feedback before async work begins
    RippleOverlay.show(at: position)

    Task { @MainActor in
      let result = await textExtractorService?.extract(at: position, frontApp: frontApp)

      let queryText = String((result?.queryText ?? "").prefix(settings.maxQueryLength))
      if !queryText.isEmpty {
        debugLog.log("Search", "Extracted: \"\(queryText)\"", level: .info)
      } else {
        debugLog.log("Search", "No text extracted", level: .debug)
      }

      // Pass full extraction result to AI provider
      ProviderRegistry.shared.aiSearchProvider.extractionResult = result

      if searchPanelController == nil {
        searchPanelController = SearchPanelController()
      }

      searchPanelController?.show(query: queryText, at: position)
    }
  }

  // MARK: - Private

  private func setupServices() {
    // Event tap for force touch
    eventTapService = EventTapService()
    eventTapService?.mouseDownPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        self?.textExtractorService?.snapshotSelection()
      }
      .store(in: &cancellables)
    eventTapService?.forceClickPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] point in
        self?.performSearch(at: point)
      }
      .store(in: &cancellables)

    // Always attempt to start — EventTapService.start() handles its own guards.
    // Permissions may be inherited (e.g. running from Xcode) even when
    // PermissionsService reports false, so let the tap/monitor try regardless.
    eventTapService?.start()

    // Text extractor
    textExtractorService = TextExtractorService()

    // Hotkey service
    hotKeyService = HotKeyService()
    hotKeyService?.hotKeyPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        self?.performSearch(at: nil)
      }
      .store(in: &cancellables)

    // Double-tap modifier service
    doubleTapService = DoubleTapService()
    doubleTapService?.doubleTapPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        self?.performSearch(at: nil)
      }
      .store(in: &cancellables)

    // Activate current hotkey
    activateHotkey(settings.hotkey)
  }

  private func activateHotkey(_ hk: Hotkey) {
    hotKeyService?.unregister()
    doubleTapService?.stop()

    switch hk {
    case .modifierTap(let mod):
      let singleTap: Bool
      if mod == .globe {
        singleTap = !PermissionsService.shared.globeKeyConflict
      } else {
        singleTap = true
      }
      doubleTapService?.start(modifier: mod, singleTap: singleTap)
    case .modifierDoubleTap(let mod):
      doubleTapService?.start(modifier: mod, singleTap: false)
    case .keyCombo(let combo):
      hotKeyService?.register(keyCombo: combo)
    case .none:
      break
    }
  }

  private func observeSettings() {
    // React to unified hotkey changes
    settings.$hotkey
      .dropFirst()
      .sink { [weak self] newHotkey in
        self?.activateHotkey(newHotkey)
      }
      .store(in: &cancellables)

    // Enable/disable event tap based on force click setting
    settings.$forceClick
      .dropFirst()
      .sink { [weak self] enabled in
        if enabled {
          self?.eventTapService?.start()
        } else {
          self?.eventTapService?.stop()
        }
      }
      .store(in: &cancellables)

    // React to permission changes (only true→false or false→true transitions)
    permissions.$accessibilityGranted
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] granted in
        guard let self = self else { return }
        if granted, self.settings.forceClick {
          self.eventTapService?.restart()
        }
      }
      .store(in: &cancellables)
  }
}
