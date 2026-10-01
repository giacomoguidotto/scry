import AppKit
import Combine
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Scry", category: "EventTap")

struct ForceClickEvent {
    let point: NSPoint
    let gestureID: UUID
}

final class EventTapService {
    struct PressureInput {
        let type: NSEvent.EventType
        let stage: Int
        let pressure: Double
    }

    // Quartz wraps trackpad pressure in its generic gesture event (29).
    // Decode through AppKit before deciding whether it is a pressure event (34).
    static let gestureEventType = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
    static let pressureEventType = CGEventType(rawValue: UInt32(NSEvent.EventType.pressure.rawValue))!
    static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << gestureEventType.rawValue)
        | (1 << pressureEventType.rawValue)

    private let pressureEventReader: (CGEvent) -> PressureInput?

    init(pressureEventReader: @escaping (CGEvent) -> PressureInput? = EventTapService.readPressureEvent) {
        self.pressureEventReader = pressureEventReader
    }

    private static func readPressureEvent(_ event: CGEvent) -> PressureInput? {
        guard let converted = NSEvent(cgEvent: event), converted.type == .pressure else { return nil }
        return PressureInput(type: converted.type, stage: converted.stage, pressure: Double(converted.pressure))
    }

    let forceClickPublisher = PassthroughSubject<ForceClickEvent, Never>()
    let mouseDownPublisher = PassthroughSubject<UUID, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthCheckTimer: Timer?
    private var passiveMonitor: Any?
    private let settings = AppSettings.shared
    fileprivate let debugLog = DebugLogStore.shared

    /// Whether force-touch detection is currently active.
    private(set) var isRunning = false

    /// True when using a passive NSEvent monitor instead of a CGEvent tap.
    private(set) var usingPassiveFallback = false

    private lazy var gestureDetector = ForceClickDetector(
        onMouseDown: { [weak self] gestureID in self?.mouseDownPublisher.send(gestureID) },
        onForceClick: { [weak self] event in
            self?.debugLog.log("EventTap", "FORCE-CLICK accepted")
            DispatchQueue.main.async { [weak self] in self?.forceClickPublisher.send(event) }
        }
    )

    func start() {
        logger.info("start() called — isRunning=\(self.isRunning), forceClick=\(self.settings.forceClick)")
        guard !isRunning else {
            debugLog.log("EventTap", "start() called but already running", level: .debug)
            return
        }
        guard settings.forceClick else {
            debugLog.log("EventTap", "start() skipped — force click is disabled", level: .debug)
            return
        }

        debugLog.log("EventTap", "Creating CGEvent tap for mouse + pressure events...")

        // Mouse events capture selection; only pressure stage two triggers lookup.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog.log("EventTap", "CGEvent.tapCreate FAILED — falling back to passive monitor", level: .warning)
            // Fallback: use passive event monitor (cannot suppress native Look Up)
            startPassiveMonitor()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        usingPassiveFallback = false
        debugLog.eventTapStatus = "Active (CGEvent tap)"
        debugLog.log("EventTap", "CGEvent tap created and enabled successfully")

        // Also start a passive monitor as a safety net — the CGEvent tap may silently
        // receive no events (e.g. inherited permissions from Xcode). The shared
        // detector permits only one lookup per press when both sources work.
        startPassiveMonitor()
        debugLog.eventTapStatus = "Active (CGEvent tap + passive)"

        // Health-check timer: re-enable tap if macOS disables it
        let timer = Timer(timeInterval: Constants.Timing.healthCheckInterval, repeats: true) { [weak self] _ in
            self?.healthCheck()
        }
        healthCheckTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Tears down and re-creates the event tap + passive monitor.
    func restart() {
        stop()
        start()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        if let monitor = passiveMonitor {
            NSEvent.removeMonitor(monitor)
            passiveMonitor = nil
        }
        eventTap = nil
        runLoopSource = nil
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        isRunning = false
        usingPassiveFallback = false
        gestureDetector.cancel()
        debugLog.eventTapStatus = "Stopped"
    }

    // MARK: - Internal (called from C callback)

    @discardableResult
    func handleStageTransition(stage: Int, pressure: Double, location: CGPoint? = nil) -> Bool {
        let point = location ?? CGEvent(source: nil)?.location ?? .zero
        return gestureDetector.pressureChanged(to: stage, at: point)
    }

    func handleMouseEvent(type: CGEventType, location: CGPoint) {
        switch type {
        case .leftMouseDown: gestureDetector.mouseDown(at: location)
        case .leftMouseUp: gestureDetector.mouseUp()
        case .leftMouseDragged: gestureDetector.mouseDragged(to: location)
        default: break
        }
    }

    // MARK: - Private

    private func startPassiveMonitor() {
        guard passiveMonitor == nil else {
            logger.info("startPassiveMonitor: already exists, skipping")
            return
        }
        logger.info("startPassiveMonitor: registering global monitor for pressure + mouse events...")
        // Note: .leftMouseDragged is NOT allowed in global monitors per Apple docs.
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.pressure, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return }

            switch event.type {
            case .pressure:
                let stage = event.stage
                let pressure = Double(event.pressure)

                let prevStage = self.gestureDetector.previousStage

                self.debugLog.log(
                    "Passive",
                    "pressure stage=\(stage) pressure=\(String(format: "%.3f", pressure)) (prev=\(prevStage))",
                    level: .debug
                )
                self.handleStageTransition(stage: stage, pressure: pressure)

            case .leftMouseDown:
                self.handlePassiveMouseDown(location: event.cgEvent?.location ?? .zero)

            case .leftMouseUp:
                self.gestureDetector.mouseUp()

            default:
                break
            }
        }
        guard let monitor = monitor else {
            logger.error("startPassiveMonitor: NSEvent.addGlobalMonitorForEvents returned nil!")
            debugLog.log("EventTap", "Passive monitor failed to register (nil returned)", level: .error)
            return
        }
        passiveMonitor = monitor
        // Only update status flags when used as sole detection method (no CGEvent tap)
        if eventTap == nil {
            isRunning = true
            usingPassiveFallback = true
            debugLog.eventTapStatus = "Passive (fallback)"
        }
        logger.info("startPassiveMonitor: registered successfully")
        debugLog.log("EventTap", "Passive monitor started")
    }

    /// Returns true only for actual pressure accepted by the detector; all other gestures pass through.
    func handleGestureEvent(type: CGEventType, event: CGEvent) -> Bool {
        guard type == Self.gestureEventType || type == Self.pressureEventType,
              let input = pressureEventReader(event), input.type == .pressure else { return false }
        debugLog.log(
            "Tap",
            "pressure raw=\(type.rawValue) stage=\(input.stage) pressure=\(String(format: "%.3f", input.pressure))",
            level: .debug
        )
        return handleStageTransition(stage: input.stage, pressure: input.pressure, location: event.location)
    }

    /// Passive delivery happens after the target receives the click. Only use it
    /// when the active tap did not already capture this press's earlier selection.
    func handlePassiveMouseDown(location: CGPoint) {
        gestureDetector.mouseDown(at: location, passive: true)
    }

    fileprivate func healthCheck() {
        guard let tap = eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            debugLog.log("EventTap", "Health check: tap was disabled, re-enabling", level: .warning)
            gestureDetector.cancel()
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func reEnableTap() {
        gestureDetector.cancel()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

/// C-level callback for CGEventTap.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()

    // Handle tap disabled events
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        service.reEnableTap()
        return Unmanaged.passUnretained(event)
    }

    // Mouse events capture the pre-click selection and reject excessive pointer drift.
    // Holding or dragging an ordinary click never triggers lookup.
    if type == .leftMouseDown || type == .leftMouseDragged || type == .leftMouseUp {
        service.handleMouseEvent(type: type, location: event.location)

        // Never suppress mouse events
        return Unmanaged.passUnretained(event)
    }

    // Quartz gesture envelopes must be decoded before testing the AppKit pressure type.
    if service.handleGestureEvent(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
