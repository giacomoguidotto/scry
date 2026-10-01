// swiftlint:disable file_length
import AppKit
import Combine
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case triggers = 1
    case permissions = 2
    case ready = 3
}

extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}

final class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep {
        didSet { UserDefaults.standard.set(currentStep.rawValue, forKey: "onboardingStep") }
    }

    let permissions = PermissionsService.shared
    let settings = AppSettings.shared

    init() {
        let saved = UserDefaults.standard.integer(forKey: "onboardingStep")
        currentStep = OnboardingStep(rawValue: saved) ?? .welcome
    }

    func nextStep() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            currentStep = next
        }
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        UserDefaults.standard.removeObject(forKey: "onboardingStep")
        permissions.stopPolling()
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
    }
}

// MARK: - Panel

final class OnboardingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        level = .normal
        isFloatingPanel = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        appearance = ScryTheme.darkAppearance

        let container = NSView(frame: contentRect(forFrameRect: frame))
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let visualEffect = NSVisualEffectView(frame: container.bounds)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.autoresizingMask = [.width, .height]
        container.addSubview(visualEffect)

        container.layer?.borderWidth = 1
        container.layer?.borderColor = ScryTheme.Colors.panelBorder.cgColor

        contentView = container
    }

    override func cancelOperation(_ sender: Any?) {
        // Block Escape — force completion
    }

    override func performClose(_ sender: Any?) {
        // Block close
    }
}

// MARK: - Content

struct OnboardingContentView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                WelcomeStepView(viewModel: viewModel)
                    .opacity(viewModel.currentStep == .welcome ? 1 : 0)
                    .offset(x: stepOffset(for: .welcome))

                TriggersStepView(viewModel: viewModel)
                    .opacity(viewModel.currentStep == .triggers ? 1 : 0)
                    .offset(x: stepOffset(for: .triggers))

                PermissionsStepView(viewModel: viewModel)
                    .opacity(viewModel.currentStep == .permissions ? 1 : 0)
                    .offset(x: stepOffset(for: .permissions))

                ReadyStepView(viewModel: viewModel)
                    .opacity(viewModel.currentStep == .ready ? 1 : 0)
                    .offset(x: stepOffset(for: .ready))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: viewModel.currentStep)

            StepIndicatorView(current: viewModel.currentStep)
                .padding(.bottom, 24)
        }
        .frame(width: 600, height: 500)
    }

    private func stepOffset(for step: OnboardingStep) -> CGFloat {
        let delta = step.rawValue - viewModel.currentStep.rawValue
        return CGFloat(delta) * 40
    }
}

struct StepIndicatorView: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(color(for: step))
                    .frame(width: step == current ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
            }
        }
    }

    private func color(for step: OnboardingStep) -> Color {
        if step == current { return ScryTheme.Colors.accentColor }
        if step.rawValue < current.rawValue { return ScryTheme.Colors.accentColor.opacity(0.4) }
        return Color.white.opacity(0.15)
    }
}

struct OnboardingButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(disabled ? ScryTheme.Colors.textTertiaryColor : .black)
                .frame(width: 220)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(disabled
                              ? ScryTheme.Colors.accentColor.opacity(0.3)
                              : ScryTheme.Colors.accentColor)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct WelcomeStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image("ScryIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: ScryTheme.Colors.accentColor.opacity(0.25), radius: 24, y: 4)

            Text("Welcome to Scry")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(ScryTheme.Colors.textPrimaryColor)

            Text("Instant search for anything on your screen.\nHighlight text, trigger Scry, get answers.")
                .font(.system(size: 15))
                .foregroundColor(ScryTheme.Colors.textSecondaryColor)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            OnboardingButton(title: "Get Started") { viewModel.nextStep() }

            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.caption)
                .foregroundColor(ScryTheme.Colors.textTertiaryColor)
                .padding(.top, 4)

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 48)
    }
}

struct TriggersStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var permissions = PermissionsService.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("How do you want to trigger Scry?")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(ScryTheme.Colors.textPrimaryColor)
                .padding(.top, 32)

            Text("You can use one or both methods.")
                .font(.system(size: 14))
                .foregroundColor(ScryTheme.Colors.textSecondaryColor)

            HStack(spacing: 16) {
                forceClickCard
                hotkeyCard
            }
            .padding(.horizontal, 32)

            Spacer()

            OnboardingButton(title: "Continue") { viewModel.nextStep() }
                .padding(.bottom, 8)
        }
    }

    private var forceClickCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "hand.tap")
                    .font(.system(size: 20))
                    .foregroundColor(ScryTheme.Colors.accentColor)
                Spacer()
                Toggle("", isOn: $settings.forceClick)
                    .toggleStyle(.switch)
                    .tint(ScryTheme.Colors.accentColor)
                    .labelsHidden()
                    .controlSize(.small)
            }

            Text("Force Click")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ScryTheme.Colors.textPrimaryColor)

            Text("Force-click on selected text")
                .font(.system(size: 12))
                .foregroundColor(ScryTheme.Colors.textSecondaryColor)

            if settings.forceClick && permissions.lookUpConflictDetected {
                conflictBanner(
                    text: "Look Up uses force-click. Change it to three-finger tap.",
                    action: "Trackpad Settings",
                    handler: { permissions.openTrackpadSettings() }
                )
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
        )
    }

    @State private var hotkeyEnabled: Bool = true
    @State private var savedHotkey: Hotkey = .modifierTap(.globe)

    private var hotkeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 20))
                    .foregroundColor(ScryTheme.Colors.accentColor)
                Spacer()
                Toggle("", isOn: $hotkeyEnabled)
                    .toggleStyle(.switch)
                    .tint(ScryTheme.Colors.accentColor)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: hotkeyEnabled) { enabled in
                        if enabled {
                            settings.hotkey = savedHotkey
                        } else {
                            savedHotkey = settings.hotkey
                            settings.hotkey = .none
                        }
                    }
            }

            Text("Hotkey")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ScryTheme.Colors.textPrimaryColor)

            Text("Press anywhere to search")
                .font(.system(size: 12))
                .foregroundColor(ScryTheme.Colors.textSecondaryColor)

            if hotkeyEnabled {
                UnifiedHotKeyRecorderView(hotkey: $settings.hotkey)
                    .frame(height: 28)

                if settings.hotkey.isGlobeTap && permissions.globeKeyConflict {
                    conflictBanner(
                        text: "Globe key has a system action. Set it to \u{201C}Do Nothing\u{201D}.",
                        action: "Keyboard Settings",
                        handler: { permissions.openKeyboardSettings() }
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
        )
    }

    private func conflictBanner(
        text: String,
        action: String,
        handler: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.9))
            }
            Button(action) { handler() }
                .font(.system(size: 11, weight: .medium))
                .controlSize(.mini)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }
}

struct PermissionsStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject private var permissions = PermissionsService.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(ScryTheme.Colors.textPrimaryColor)
                .padding(.top, 32)

            Text("Scry needs a couple of permissions to work.")
                .font(.system(size: 14))
                .foregroundColor(ScryTheme.Colors.textSecondaryColor)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "lock.shield",
                    grantedIcon: "checkmark.shield.fill",
                    title: "Accessibility",
                    subtitle: "Read selected text and detect triggers",
                    granted: permissions.accessibilityGranted,
                    required: true,
                    action: { permissions.requestAccessibility() }
                )

                permissionRow(
                    icon: "eye.slash",
                    grantedIcon: "eye",
                    title: "Screen Recording",
                    subtitle: "Detect text under cursor via OCR",
                    granted: permissions.screenRecordingGranted,
                    required: false,
                    action: {
                        permissions.requestScreenRecording()
                        permissions.startPollingWithScreenRecording()
                    }
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            if permissions.accessibilityGranted {
                OnboardingButton(title: "Continue") {
                    viewModel.nextStep()
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            permissions.checkScreenRecording()
            permissions.startPolling()
        }
        .onDisappear {
            permissions.stopPolling()
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func permissionRow(
        icon: String,
        grantedIcon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        required: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? grantedIcon : icon)
                .font(.system(size: 24))
                .foregroundColor(
                    granted ? ScryTheme.Colors.accentColor : ScryTheme.Colors.textSecondaryColor
                )
                .frame(width: 36)
                .animation(.spring(response: 0.4), value: granted)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ScryTheme.Colors.textPrimaryColor)
                    if required {
                        Text("Required")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ScryTheme.Colors.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(ScryTheme.Colors.accentColor.opacity(0.15))
                            )
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(ScryTheme.Colors.textSecondaryColor)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(ScryTheme.Colors.accentColor)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Grant") { action() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(ScryTheme.Colors.accentColor)
                    )
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
        )
    }
}

struct ReadyStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var pulseOpacity: Double = 0.4

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(ScryTheme.Colors.accentColor)

            Text("You\u{2019}re All Set!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(ScryTheme.Colors.textPrimaryColor)

            VStack(spacing: 12) {
                if settings.forceClick {
                    triggerRow(
                        icon: "hand.tap",
                        label: "Force Click",
                        detail: "Force-click on any selected text"
                    )
                }
                if settings.hotkey != .none {
                    triggerRow(
                        icon: "keyboard",
                        label: settings.hotkey.displayString,
                        detail: "Press anywhere to search"
                    )
                }
            }
            .padding(.horizontal, 48)

            Spacer()

            Text("Try it now \u{2014} trigger Scry to begin")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ScryTheme.Colors.textSecondaryColor)
                .opacity(pulseOpacity)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: pulseOpacity
                )
                .onAppear { pulseOpacity = 1.0 }

            Button("or press here to finish") {
                viewModel.completeOnboarding()
            }
            .font(.system(size: 12))
            .foregroundColor(ScryTheme.Colors.textTertiaryColor)
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
    }

    private func triggerRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(ScryTheme.Colors.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ScryTheme.Colors.textPrimaryColor)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(ScryTheme.Colors.textSecondaryColor)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var panel: OnboardingPanel?
    private var viewModel: OnboardingViewModel?
    private var cancellables = Set<AnyCancellable>()

    /// Called once when onboarding reaches step 4 (services needed for trigger demo).
    var onServicesNeeded: (() -> Void)?
    private var servicesStarted = false

    var isOnStepFour: Bool {
        viewModel?.currentStep == .ready
    }

    func show() {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let vm = OnboardingViewModel()
        self.viewModel = vm

        let content = OnboardingContentView(viewModel: vm)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: 600, height: 500))

        let onboardingPanel = OnboardingPanel(size: NSSize(width: 600, height: 500))

        // Add hosting view inside the container (which has the frosted glass)
        if let container = onboardingPanel.contentView {
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }

        onboardingPanel.center()
        onboardingPanel.delegate = self
        onboardingPanel.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = onboardingPanel

        // Start services when reaching step 4 (trigger demo needs them)
        vm.$currentStep
            .filter { $0 == .ready }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.servicesStarted else { return }
                self.servicesStarted = true
                self.onServicesNeeded?()
            }
            .store(in: &cancellables)

        // Listen for completion (from "press here to finish" button or trigger)
        NotificationCenter.default.publisher(for: .onboardingCompleted)
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dismissAnimated()
            }
            .store(in: &cancellables)
    }

    /// Called by AppDelegate when the user triggers a search on step 4.
    func dismissForSearch() {
        viewModel?.completeOnboarding()
    }

    private func dismissAnimated() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel = nil
            self?.viewModel = nil
            self?.cancellables.removeAll()
            AppActivationPolicy.updatePolicy()
        })
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        viewModel = nil
        cancellables.removeAll()
        AppActivationPolicy.updatePolicy()
    }
}
