import SwiftUI

struct ShortcutsPreferencesView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var permissions = PermissionsService.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Scry Hotkey")
                    Spacer()
                    UnifiedHotKeyRecorderView(hotkey: $settings.hotkey)
                        .frame(width: 160, height: 28)
                }

                if showGlobeWarning {
                    globeConflictBanner
                }
            } header: {
                Label("Hotkey", systemImage: "keyboard")
            } footer: {
                Text(hotkeyFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Force Click", isOn: $settings.forceClick)

                if settings.forceClick {
                    Text("Press firmly through the trackpad’s second click on selected text.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Force Click", systemImage: "hand.tap")
            }

            Section("Keyboard Shortcuts") {
                shortcutRow(hotkeyDisplayLabel, "Scry hotkey")
                shortcutRow("Force Click", "Force-click on selected text")
                shortcutRow("\u{238B}", "Close panel")
                shortcutRow("\u{2318} 1\u{2013}9", "Switch provider tabs")
                shortcutRow("\u{2318} \u{21A9}", "Open in browser")
                shortcutRow("\u{2318} C", "Copy URL")
                shortcutRow("\u{2318} ,", "Preferences")
                shortcutRow("\u{2318} \u{232B}", "Clear search")
                shortcutRow("\u{21A9}", "Search")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
    }

    // MARK: - Globe Warning

    private var showGlobeWarning: Bool {
        settings.hotkey.isGlobeTap && permissions.globeKeyConflict
    }

    private var globeConflictBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            VStack(alignment: .leading, spacing: 4) {
                Text("Globe key has a system action assigned")
                    .font(.caption).fontWeight(.medium)
                // swiftlint:disable:next line_length
                Text("Set \u{201C}Press Globe key\u{201D} to \u{201C}Do Nothing\u{201D} in **System Settings \u{2192} Keyboard** for single-tap. Double-tap works regardless.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Keyboard Settings") {
                    permissions.openKeyboardSettings()
                }
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Computed

    private var hotkeyFooter: String {
        switch settings.hotkey {
        case .modifierTap(let mod):
            if mod == .globe && !permissions.globeKeyConflict {
                return "Tap the Globe key to trigger a search."
            }
            if mod == .globe {
                return "Tap the modifier key twice to trigger a search."
            }
            return "Tap the modifier key to trigger a search."
        case .modifierDoubleTap:
            return "Tap the modifier key twice to trigger a search."
        case .keyCombo(let combo):
            return "Press \(combo.displayString) anywhere to trigger a search."
        case .none:
            return "Record a shortcut to trigger Scry from anywhere."
        }
    }

    private var hotkeyDisplayLabel: String {
        switch settings.hotkey {
        case .modifierTap(let mod):
            if mod == .globe && !permissions.globeKeyConflict {
                return mod.symbol
            }
            if mod == .globe {
                return "\(mod.symbol) \(mod.symbol)"
            }
            return mod.symbol
        case .modifierDoubleTap(let mod):
            return "\(mod.symbol) \(mod.symbol)"
        case .keyCombo(let combo):
            return combo.displayString
        case .none:
            return "None"
        }
    }

    @ViewBuilder
    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
                .frame(width: 100, alignment: .leading)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Unified Hotkey Recorder

/// A single recorder field: click to record, then either:
/// - Press modifier+key for a standard hotkey
/// - Tap a modifier key twice for a double-tap trigger
/// - Tap Globe once (if set to "Do Nothing")
/// Press Escape or Delete to clear. Click again to cancel.
struct UnifiedHotKeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> UnifiedHotKeyRecorderNSView {
        let view = UnifiedHotKeyRecorderNSView()
        view.onResult = { result in
            switch result {
            case let .keyCombo(combo):
                hotkey = .keyCombo(combo)
            case let .doubleTapModifier(modifier):
                if modifier == .globe {
                    hotkey = .modifierTap(.globe)
                } else {
                    hotkey = .modifierDoubleTap(modifier)
                }
            case .cleared:
                hotkey = .none
            }
        }
        return view
    }

    func updateNSView(_ nsView: UnifiedHotKeyRecorderNSView, context: Context) {
        nsView.displayText = currentDisplayText
        nsView.updateDisplay()
    }

    private var currentDisplayText: String {
        switch hotkey {
        case .modifierTap(let mod):
            if mod == .globe && !PermissionsService.shared.globeKeyConflict {
                return mod.symbol
            }
            if mod == .globe {
                return "\(mod.symbol) \(mod.symbol)"
            }
            return mod.symbol
        case .modifierDoubleTap(let mod):
            return "\(mod.symbol) \(mod.symbol)"
        case .keyCombo(let combo):
            return combo.displayString
        case .none:
            return "Record Hotkey"
        }
    }
}

enum HotKeyRecorderResult {
    case keyCombo(KeyCombo)
    case doubleTapModifier(DoubleTapModifier)
    case cleared
}

final class UnifiedHotKeyRecorderNSView: NSView {
    var onResult: ((HotKeyRecorderResult) -> Void)?
    var displayText: String = "Record Hotkey"

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false
    private var keyMonitor: Any?
    private var flagsMonitor: Any?

    /// Track modifier-only taps for double-tap detection.
    private var lastModifierDown: (keyCode: UInt16, time: Date)?
    private var lastModifierTap: (keyCode: UInt16, time: Date)?

    private static let maxTapDuration: TimeInterval = 0.4
    private static let maxDoubleTapInterval: TimeInterval = 0.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit { stopRecording() }

    func updateDisplay() {
        guard !isRecording else { return }
        label.stringValue = displayText
        label.textColor = hasHotkey ? .labelColor : .tertiaryLabelColor
    }

    private var hasHotkey: Bool {
        displayText != "Record Hotkey"
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(click)

        updateDisplay()
    }

    @objc private func clicked() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        lastModifierDown = nil
        lastModifierTap = nil
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        label.stringValue = "Type shortcut\u{2026}"
        label.textColor = .controlAccentColor

        // Listen for key combos (modifier + key)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Escape = clear
            if event.keyCode == 53 {
                self.onResult?(.cleared)
                self.stopRecording()
                return nil
            }

            // Delete = clear
            if event.keyCode == 51 {
                self.onResult?(.cleared)
                self.stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Need at least one modifier for a key combo
            guard !flags.isEmpty else { return event }

            let combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: flags)
            self.onResult?(.keyCombo(combo))
            self.stopRecording()
            return nil
        }

        // Listen for modifier-only taps (double-tap detection)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        guard let modifier = modifierForKeyCode(keyCode) else { return }

        // Check if other modifiers are held (chord — ignore)
        let allFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
        let thisFlag = modifier.modifierFlag
        let others = allFlags.subtracting(thisFlag)
        guard event.modifierFlags.isDisjoint(with: others) else {
            lastModifierDown = nil
            lastModifierTap = nil
            return
        }

        let isDown = event.modifierFlags.contains(thisFlag)

        if isDown {
            // Modifier key down
            lastModifierDown = (keyCode, Date())
        } else if let down = lastModifierDown, down.keyCode == keyCode {
            // Modifier key up — was it a quick tap?
            let now = Date()
            let duration = now.timeIntervalSince(down.time)
            lastModifierDown = nil

            guard duration < Self.maxTapDuration else {
                lastModifierTap = nil
                return
            }

            // Globe single-tap: if Globe is set to "Do Nothing", one tap is enough
            if modifier == .globe && !PermissionsService.shared.globeKeyConflict {
                onResult?(.doubleTapModifier(.globe))
                stopRecording()
                return
            }

            // Check for double-tap
            if let prev = lastModifierTap, prev.keyCode == keyCode,
               now.timeIntervalSince(prev.time) < Self.maxDoubleTapInterval {
                lastModifierTap = nil
                onResult?(.doubleTapModifier(modifier))
                stopRecording()
            } else {
                lastModifierTap = (keyCode, now)
                // Show the modifier symbol as feedback
                label.stringValue = "\(modifier.symbol) \u{2026}"
            }
        }
    }

    private func modifierForKeyCode(_ keyCode: UInt16) -> DoubleTapModifier? {
        for modifier in DoubleTapModifier.allCases {
            if keyCode == modifier.keyCode || keyCode == modifier.rightKeyCode {
                return modifier
            }
        }
        return nil
    }

    private func stopRecording() {
        isRecording = false
        lastModifierDown = nil
        lastModifierTap = nil
        layer?.borderColor = NSColor.separatorColor.cgColor
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        updateDisplay()
    }
}

// MARK: - DoubleTapModifier Symbol

extension DoubleTapModifier {
    var symbol: String {
        switch self {
        case .globe: return "fn"
        case .command: return "\u{2318}"
        case .option: return "\u{2325}"
        case .control: return "\u{2303}"
        case .shift: return "\u{21E7}"
        }
    }
}
