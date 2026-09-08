import AppKit

struct WindowMovement {
    static func origin(frame: CGRect, visible: CGRect, dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: min(max(frame.minX + dx, visible.minX), max(visible.minX, visible.maxX - frame.width)),
                y: min(max(frame.minY + dy, visible.minY), max(visible.minY, visible.maxY - frame.height)))
    }
}

@MainActor final class WindowMover {
    weak var panel: NSPanel?
    private var held = Set<UInt32>()
    private var timer: Timer?
    private var lastTick = Date()

    func key(_ direction: UInt32, pressed: Bool) {
        if pressed {
            guard panel?.isVisible == true else { return }
            let inserted = held.insert(direction).inserted
            if inserted { step(seconds: 1.0 / 30) }
            if timer == nil {
                lastTick = Date()
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                self.timer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        } else {
            held.remove(direction)
            if held.isEmpty { stop() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; held.removeAll() }
    private func tick() {
        let now = Date()
        let elapsed = min(0.05, now.timeIntervalSince(lastTick))
        lastTick = now
        step(seconds: elapsed)
    }
    private func step(seconds: Double) {
        guard let panel, panel.isVisible, let screen = panel.screen ?? NSScreen.main else { stop(); return }
        let x = (held.contains(5) ? 1.0 : 0) - (held.contains(4) ? 1.0 : 0)
        let y = (held.contains(6) ? 1.0 : 0) - (held.contains(7) ? 1.0 : 0)
        let scale = (x != 0 && y != 0) ? 0.70710678 : 1
        panel.setFrameOrigin(WindowMovement.origin(frame: panel.frame, visible: screen.visibleFrame, dx: x * 420 * seconds * scale, dy: y * 420 * seconds * scale))
    }
}
