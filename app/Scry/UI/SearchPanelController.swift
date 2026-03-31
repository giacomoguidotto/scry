import AppKit
import Combine

final class SearchPanelController: NSObject {
    private var panel: SearchPanel?
    private let settings = AppSettings.shared
    private let registry = ProviderRegistry.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchBar: SearchBarView!
    private var tabBar: ProviderTabBar!
    private var webViewController: SearchWebViewController!
    private var nativeResultView: NativeResultView!
    private var aiResultView: AIResultView!
    private var loadingBar: NSView!
    private var contentContainer: NSView!
    private var placeholderLabel: NSTextField!
    private var grantButton: NSButton!
    private var currentQuery = ""
    private var currentProviders: [SearchProvider] = []
    private var selectedProviderIndex = 0
    private var clickOutsideMonitor: Any?
    private var webViewCache: [String: SearchWebViewController] = [:]
    private var cachedQuery = ""
    private var cursorPoint: NSPoint = .zero

    func show(query: String, at point: NSPoint) {
        // If panel is already visible, just update the query and re-search
        if let panel = panel, panel.isVisible {
            currentQuery = query
            searchBar.query = query
            clearWebViewCache()
            performSearch()
            panel.makeKeyAndOrderFront(nil)
            searchBar.focus()
            return
        }

        currentQuery = query
        cursorPoint = point
        currentProviders = registry.enabledProviders()

        guard !currentProviders.isEmpty else { return }

        // Determine initial provider
        let effectiveID = settings.effectiveProvider
        selectedProviderIndex = currentProviders.firstIndex(where: { $0.id == effectiveID }) ?? 0

        if panel == nil {
            createPanel()
        }

        // Configure UI
        searchBar.query = query
        tabBar.configure(providers: currentProviders, selectedIndex: selectedProviderIndex)

        // Position panel
        let panelFrame = calculateFrame(near: point)
        panel?.setFrame(panelFrame, display: false)

        // Show with animation
        showWithAnimation()

        // Load search or show hint for empty query
        if query.isEmpty {
            showPlaceholder(
                "Grant Screen Recording to enable text detection under cursor.",
                showGrant: true,
                grantHandler: { PermissionsService.shared.requestScreenRecording() }
            )
        } else {
            performSearch()
        }

        // Monitor for clicks outside
        startClickOutsideMonitor()

        // Listen for keyboard events
        startKeyMonitor()
    }

    func showAccessibilityPrompt(at point: NSPoint) {
        currentQuery = ""
        cursorPoint = point
        currentProviders = registry.enabledProviders()
        guard !currentProviders.isEmpty else { return }

        selectedProviderIndex = 0
        if panel == nil { createPanel() }

        searchBar.query = ""
        tabBar.configure(providers: currentProviders, selectedIndex: selectedProviderIndex)

        let panelFrame = calculateFrame(near: point)
        panel?.setFrame(panelFrame, display: false)
        showWithAnimation()

        showPlaceholder(
            "Accessibility permission required to read text.",
            showGrant: true,
            grantHandler: { PermissionsService.shared.requestAccessibility() }
        )
        startClickOutsideMonitor()
        startKeyMonitor()
    }

    func dismiss() {
        guard let panel = panel, panel.isVisible else { return }

        stopClickOutsideMonitor()
        stopKeyMonitor()

        if settings.showAnimations {
            dismissWithAnimation {
                self.cleanup()
            }
        } else {
            panel.orderOut(nil)
            cleanup()
        }
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let panel = SearchPanel()
        self.panel = panel

        guard let contentView = panel.contentView else { return }

        searchBar = SearchBarView()
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(searchBar)

        tabBar = ProviderTabBar()
        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabBar)

        loadingBar = NSView()
        loadingBar.wantsLayer = true
        loadingBar.layer?.backgroundColor = ScryTheme.Colors.accent.cgColor
        loadingBar.isHidden = true
        loadingBar.translatesAutoresizingMaskIntoConstraints = false

        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentContainer)

        placeholderLabel = NSTextField(labelWithString: "Searching…")
        placeholderLabel.font = .systemFont(ofSize: 14, weight: .medium)
        placeholderLabel.textColor = ScryTheme.Colors.textTertiary
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(placeholderLabel)

        grantButton = NSButton(title: "Grant", target: self, action: #selector(handleGrant))
        grantButton.bezelStyle = .rounded
        grantButton.controlSize = .regular
        grantButton.isHidden = true
        grantButton.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(grantButton)

        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor, constant: -12),
            grantButton.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            grantButton.topAnchor.constraint(equalTo: placeholderLabel.bottomAnchor, constant: 12),
        ])

        webViewController = SearchWebViewController()
        webViewController.delegate = self
        webViewController.webView.translatesAutoresizingMaskIntoConstraints = false
        webViewController.webView.loadHTMLString("", baseURL: nil)

        nativeResultView = NativeResultView()
        nativeResultView.translatesAutoresizingMaskIntoConstraints = false
        aiResultView = AIResultView()
        aiResultView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            searchBar.heightAnchor.constraint(equalToConstant: Constants.Panel.searchBarHeight),

            tabBar.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: Constants.Panel.tabBarHeight),

            contentContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        // Loading bar overlays the top of the content area (not in layout flow)
        contentView.addSubview(loadingBar, positioned: .above, relativeTo: contentContainer)
        NSLayoutConstraint.activate([
            loadingBar.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            loadingBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            loadingBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            loadingBar.heightAnchor.constraint(equalToConstant: AnimationConstants.Loading.barHeight),
        ])

        // Listen for panel events
        NotificationCenter.default.publisher(for: .searchPanelEscapePressed)
            .sink { [weak self] _ in self?.dismiss() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .searchPanelDidResignKey)
            .sink { [weak self] _ in self?.dismiss() }
            .store(in: &cancellables)
    }

    // MARK: - Content Display

    private func embedInContentContainer(_ view: NSView) {
        guard view.superview !== contentContainer else { return }
        view.removeFromSuperview()
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private var grantAction: (() -> Void)?

    private func showPlaceholder(_ text: String, showGrant: Bool = false, grantHandler: (() -> Void)? = nil) {
        webViewController.webView.removeFromSuperview()
        nativeResultView.removeFromSuperview()
        aiResultView.removeFromSuperview()

        placeholderLabel.stringValue = text
        placeholderLabel.isHidden = false
        grantButton.isHidden = !showGrant
        grantAction = grantHandler
    }

    private func hidePlaceholder() {
        placeholderLabel.isHidden = true
        grantButton.isHidden = true
        grantAction = nil
    }

    @objc private func handleGrant() {
        grantAction?()
    }

    private func showWebContent(for provider: SearchProvider) {
        nativeResultView.removeFromSuperview()
        aiResultView.removeFromSuperview()

        // Invalidate cache if query changed
        if cachedQuery != currentQuery {
            clearWebViewCache()
            cachedQuery = currentQuery
        }

        // Reuse cached web view controller for this provider, or create a new one
        let controller: SearchWebViewController
        if let cached = webViewCache[provider.id] {
            controller = cached
        } else {
            controller = SearchWebViewController()
            controller.delegate = self
            webViewCache[provider.id] = controller
        }

        // Remove the previous web view from display
        webViewController.webView.removeFromSuperview()
        webViewController = controller

        // Show loading placeholder until the page finishes (only for uncached loads)
        showPlaceholder("Searching…")

        let wv = controller.webView
        wv.translatesAutoresizingMaskIntoConstraints = false
        embedInContentContainer(wv)

        // If this page was already loaded for the same query, skip the network request
        if controller.currentURL != nil && cachedQuery == currentQuery {
            hidePlaceholder()
            loadingBar.isHidden = true
            stopLoadingAnimation()
        } else {
            controller.search(query: currentQuery, provider: provider)
        }
    }

    private func clearWebViewCache() {
        for (_, controller) in webViewCache {
            controller.stopLoading()
        }
        webViewCache.removeAll()
    }

    private func showAIContent(for provider: AISearchProvider) {
        webViewController.webView.removeFromSuperview()
        webViewController.stopLoading()
        nativeResultView.removeFromSuperview()
        embedInContentContainer(aiResultView)

        hidePlaceholder()
        loadingBar.isHidden = false
        startLoadingAnimation()

        let response = provider.startAnalysis()
        aiResultView.observe(response: response)

        Task {
            while !response.isComplete {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            await MainActor.run {
                loadingBar.isHidden = true
                stopLoadingAnimation()
            }
        }
    }

    private func showNativeContent(for provider: SearchProvider) {
        webViewController.webView.removeFromSuperview()
        webViewController.stopLoading()
        aiResultView.removeFromSuperview()
        embedInContentContainer(nativeResultView)

        hidePlaceholder()
        loadingBar.isHidden = false
        startLoadingAnimation()

        Task {
            do {
                let results = try await provider.search(query: currentQuery)
                await MainActor.run {
                    nativeResultView.display(results: results)
                    loadingBar.isHidden = true
                    stopLoadingAnimation()
                }
            } catch {
                await MainActor.run {
                    nativeResultView.display(
                        results: [],
                        errorMessage: "Search failed — please try again."
                    )
                    loadingBar.isHidden = true
                    stopLoadingAnimation()
                }
            }
        }
    }

    // MARK: - Search

    private func performSearch() {
        guard selectedProviderIndex < currentProviders.count else { return }
        let provider = currentProviders[selectedProviderIndex]

        settings.lastUsedProvider = provider.id

        if let aiProvider = provider as? AISearchProvider {
            showAIContent(for: aiProvider)
        } else if provider.supportsNativeRendering {
            showNativeContent(for: provider)
        } else {
            showWebContent(for: provider)
        }
    }

    // MARK: - Positioning

    private func calculateFrame(near point: NSPoint) -> NSRect {
        let (w, h, margin) = (settings.panelWidth, settings.panelHeight, Constants.Panel.edgeMargin)
        let screenFrame = NSScreen.visibleFrameContaining(point: point)
        var origin = NSPoint(x: point.x - w / 2, y: point.y - h - 20)
        if origin.y < screenFrame.minY + margin { origin.y = point.y + 20 }
        return NSScreen.clampedFrame(
            NSRect(origin: origin, size: NSSize(width: w, height: h)), to: screenFrame, margin: margin
        )
    }

    // MARK: - Animations

    private func showWithAnimation() {
        guard let panel = panel else { return }

        if settings.showAnimations {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)

            guard let contentView = panel.contentView else { return }
            contentView.wantsLayer = true
            guard let layer = contentView.layer else { return }

            // Calculate directional offset from panel center toward cursor
            let panelCenter = NSPoint(
                x: panel.frame.midX,
                y: panel.frame.midY
            )
            let fraction = AnimationConstants.PanelShow.cursorTranslationFraction
            let dx = (cursorPoint.x - panelCenter.x) * fraction
            let dy = (cursorPoint.y - panelCenter.y) * fraction
            let scale = AnimationConstants.PanelShow.initialScale

            // Initial transform: translate toward cursor + scale down
            var initial = CATransform3DIdentity
            initial = CATransform3DTranslate(initial, dx, dy, 0)
            initial = CATransform3DScale(initial, scale, scale, 1)
            layer.transform = initial

            // Spring animation on transform
            let spring = CASpringAnimation(keyPath: "transform")
            spring.mass = AnimationConstants.PanelShow.springMass
            spring.stiffness = AnimationConstants.PanelShow.springStiffness
            spring.damping = AnimationConstants.PanelShow.springDamping
            spring.fromValue = NSValue(caTransform3D: initial)
            spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.duration = spring.settlingDuration
            spring.fillMode = .forwards
            spring.isRemovedOnCompletion = true
            layer.transform = CATransform3DIdentity
            layer.add(spring, forKey: "bloomTransform")

            // Fade in opacity
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.0
            fade.toValue = Float(settings.panelOpacity)
            fade.duration = AnimationConstants.PanelShow.opacityDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.alphaValue = CGFloat(settings.panelOpacity)
            panel.contentView?.layer?.add(fade, forKey: "bloomOpacity")
        } else {
            panel.alphaValue = CGFloat(settings.panelOpacity)
            panel.makeKeyAndOrderFront(nil)
        }

        searchBar.focus()
    }

    private func dismissWithAnimation(completion: @escaping () -> Void) {
        guard let panel = panel else {
            completion()
            return
        }

        guard let contentView = panel.contentView else {
            panel.orderOut(nil)
            completion()
            return
        }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else {
            panel.orderOut(nil)
            completion()
            return
        }

        let duration = AnimationConstants.PanelDismiss.duration
        let curve = CAMediaTimingFunction(
            controlPoints: AnimationConstants.PanelDismiss.curveP1x,
            AnimationConstants.PanelDismiss.curveP1y,
            AnimationConstants.PanelDismiss.curveP2x,
            AnimationConstants.PanelDismiss.curveP2y
        )

        // Scale down
        let finalScale = AnimationConstants.PanelDismiss.finalScale
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.toValue = finalScale
        scaleAnim.duration = duration
        scaleAnim.timingFunction = curve
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false

        // Fade out
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.toValue = 0.0
        fadeAnim.duration = duration
        fadeAnim.timingFunction = curve
        fadeAnim.fillMode = .forwards
        fadeAnim.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            panel.orderOut(nil)
            completion()
        }
        layer.add(scaleAnim, forKey: "dismissScale")
        layer.add(fadeAnim, forKey: "dismissFade")
        panel.alphaValue = 0
        CATransaction.commit()
    }

    private func startLoadingAnimation() {
        loadingBar.wantsLayer = true
        let anim = CABasicAnimation(keyPath: "position.x")
        anim.fromValue = -100
        anim.toValue = settings.panelWidth + 100
        anim.duration = 1.0
        anim.repeatCount = .infinity
        loadingBar.layer?.add(anim, forKey: "loading")
    }
    private func stopLoadingAnimation() {
        loadingBar.layer?.removeAnimation(forKey: "loading")
    }

    // MARK: - Click Outside / Key Monitor
    private var keyMonitor: Any?

    private func startClickOutsideMonitor() {
        stopClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let panel = self.panel, panel.isVisible else { return }
            let screenPoint = NSEvent.mouseLocation
            if !panel.frame.contains(screenPoint) {
                self.dismiss()
            }
        }
    }

    private func stopClickOutsideMonitor() {
        clickOutsideMonitor.map { NSEvent.removeMonitor($0) }
        clickOutsideMonitor = nil
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape → dismiss
        if event.keyCode == 53 { // kVK_Escape
            dismiss()
            return true
        }

        // Cmd+1..9 → switch tabs
        if flags.contains(.command), let num = Int(event.charactersIgnoringModifiers ?? ""), num >= 1, num <= 9 {
            let index = num - 1
            if index < currentProviders.count {
                selectedProviderIndex = index
                tabBar.selectTab(at: index)
                performSearch()
            }
            return true
        }

        // Cmd+Return → open in browser
        if flags.contains(.command) && event.keyCode == 36 { // kVK_Return
            openInBrowser()
            return true
        }

        // Cmd+C → copy URL
        if flags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copyURL()
            return true
        }

        // Cmd+, → open preferences
        if flags.contains(.command) && event.keyCode == 43 { // kVK_ANSI_Comma
            AppDelegate.shared?.showPreferences()
            return true
        }

        // Cmd+Delete → clear search
        if flags.contains(.command) && event.keyCode == 51 { // kVK_Delete
            searchBar.query = ""
            return true
        }

        return false
    }

    // MARK: - Actions

    private func openInBrowser() {
        guard let url = currentBrowserURL() else { return }
        let target = settings.openLinksIn
        if let bundleID = target.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }

    private func copyURL() {
        guard let url = currentBrowserURL() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func currentBrowserURL() -> URL? {
        if let url = webViewController.currentURL {
            return url
        }
        // For native providers, construct a search URL
        guard selectedProviderIndex < currentProviders.count else { return nil }
        return currentProviders[selectedProviderIndex].searchURL(for: currentQuery)
    }

    private func cleanup() {
        webViewController.stopLoading()
        clearWebViewCache()
        aiResultView.clear()
    }
}

// MARK: - SearchBarDelegate

extension SearchPanelController: SearchBarDelegate {
    func searchBarDidChangeQuery(_ query: String) {
        // Debounce handled by the user pressing Return
    }

    func searchBarDidPressReturn() {
        currentQuery = String(searchBar.query.prefix(settings.maxQueryLength))
        performSearch()
    }

    func searchBarDidPressClearButton() {
        currentQuery = ""
    }
}

// MARK: - ProviderTabBarDelegate

extension SearchPanelController: ProviderTabBarDelegate {
    func tabBar(_ tabBar: ProviderTabBar, didSelectProviderAt index: Int) {
        guard index != selectedProviderIndex else { return }
        selectedProviderIndex = index

        // Show loading indicator during tab switch
        loadingBar.isHidden = false
        startLoadingAnimation()

        // Cross-fade animation
        if settings.showAnimations {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = AnimationConstants.TabSwitch.contentFadeDuration
                contentContainer.animator().alphaValue = 0
            } completionHandler: {
                self.performSearch()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = AnimationConstants.TabSwitch.contentFadeDuration
                    self.contentContainer.animator().alphaValue = 1
                }
            }
        } else {
            performSearch()
        }
    }
}

// MARK: - SearchWebViewDelegate

extension SearchPanelController: SearchWebViewDelegate {
    func webViewDidStartLoading() {
        loadingBar.isHidden = false
        startLoadingAnimation()
    }

    func webViewDidFinishLoading() {
        hidePlaceholder()
        loadingBar.isHidden = true
        stopLoadingAnimation()
    }

    func webViewDidFailLoading(error: Error) {
        loadingBar.isHidden = true
        stopLoadingAnimation()
        showPlaceholder("Search failed — please try again.")
    }

    func webViewRequestedExternalNavigation(url: URL) {
        let target = settings.openLinksIn
        if let bundleID = target.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }

        if settings.dismissOnLinkClick {
            dismiss()
        }
    }
}
