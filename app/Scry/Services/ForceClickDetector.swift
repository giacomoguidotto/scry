import AppKit

/// Per-press detection, shared by the active tap and passive monitor.
/// Mouse events capture selection and track drift; only pressure stage two fires.
final class ForceClickDetector {
    private struct Press {
        let id: UUID
        let location: CGPoint
        var fired = false
        var driftExceeded = false
    }

    private let lock = NSLock()
    private var press: Press?
    private var stage = 0
    private var lastFireTime = -TimeInterval.infinity
    private let now: () -> TimeInterval
    private let onMouseDown: (UUID) -> Void
    private let onForceClick: (ForceClickEvent) -> Void

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onMouseDown: @escaping (UUID) -> Void,
        onForceClick: @escaping (ForceClickEvent) -> Void
    ) {
        self.now = now
        self.onMouseDown = onMouseDown
        self.onForceClick = onForceClick
    }

    var previousStage: Int {
        lock.lock()
        defer { lock.unlock() }
        return stage
    }

    func mouseDown(at location: CGPoint, passive: Bool = false) {
        lock.lock()
        // Passive delivery follows the original click; preserve the earlier AX snapshot.
        guard !passive || press == nil else {
            lock.unlock()
            return
        }
        let id = UUID()
        press = Press(id: id, location: location)
        stage = 0
        lock.unlock()

        // Synchronous, with no detector lock held, before the tap forwards the click.
        onMouseDown(id)
    }

    func mouseUp() {
        lock.lock()
        press = nil
        stage = 0
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        press = nil
        stage = 0
        lastFireTime = -TimeInterval.infinity
        lock.unlock()
    }

    func mouseDragged(to location: CGPoint) {
        lock.lock()
        defer { lock.unlock() }
        guard let current = press else { return }
        if exceedsDrift(from: current.location, to: location) {
            press?.driftExceeded = true
        }
    }

    /// Return true only for an accepted stage-two press, allowing native Look Up suppression.
    func pressureChanged(to newStage: Int, at location: CGPoint) -> Bool {
        lock.lock()
        let transitioned = stage < 2 && newStage == 2
        stage = newStage
        guard newStage == 2, var current = press else {
            lock.unlock()
            return false
        }
        if current.fired {
            lock.unlock()
            return true
        }
        guard transitioned, !current.driftExceeded else {
            lock.unlock()
            return false
        }
        guard !exceedsDrift(from: current.location, to: location) else {
            press?.driftExceeded = true
            lock.unlock()
            return false
        }
        let time = now()
        guard time - lastFireTime > Constants.Timing.debounceCooldown else {
            lock.unlock()
            return false
        }
        current.fired = true
        press = current
        lastFireTime = time
        lock.unlock()

        onForceClick(ForceClickEvent(point: NSScreen.convertFromTopLeft(location), gestureID: current.id))
        return true
    }

    private func exceedsDrift(from start: CGPoint, to location: CGPoint) -> Bool {
        let dx = location.x - start.x
        let dy = location.y - start.y
        return dx * dx + dy * dy > 16
    }
}
