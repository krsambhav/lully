import AppKit

struct WindowResize {
    static func frame(_ frame: CGRect, factor: CGFloat, minimum: CGSize, visible: CGRect) -> CGRect {
        let width = min(visible.width, max(minimum.width, frame.width * factor))
        let height = min(visible.height, max(minimum.height, frame.height * factor))
        let x = min(max(frame.midX - width / 2, visible.minX), visible.maxX - width)
        let y = min(max(frame.midY - height / 2, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor final class WindowResizer {
    private weak var panel: NSPanel?
    private var monitor: Any?
    private var timer: Timer?
    private var target: CGRect?
    private var lastTick = Date()

    func start(panel: NSPanel, enabled: @escaping () -> Bool) {
        self.panel = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panel.isKeyWindow, enabled() else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) else { return event }
            let key = event.charactersIgnoringModifiers ?? ""
            // Accept both ⌘= and ⌘⇧=, plus numeric-keypad +/-.
            guard ["+", "=", "-", "_"].contains(key) else { return event }
            self.resize(larger: key == "+" || key == "=")
            return nil
        }
    }

    private func resize(larger: Bool) {
        guard let panel, let screen = panel.screen else { return }
        target = WindowResize.frame(target ?? panel.frame, factor: larger ? 1.07 : 1 / 1.07, minimum: panel.minSize, visible: screen.visibleFrame)
        guard timer == nil else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard let panel, panel.isVisible, panel.isKeyWindow, let target else { stop(); return }
        let now = Date()
        let amount = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 1 - exp(-24 * min(0.05, now.timeIntervalSince(lastTick)))
        lastTick = now
        let frame = panel.frame
        let difference = abs(frame.width - target.width) + abs(frame.height - target.height)
        if difference < 0.5 || amount == 1 {
            panel.setFrame(target, display: true)
            stop()
        } else {
            panel.setFrame(CGRect(x: frame.minX + (target.minX - frame.minX) * amount,
                                  y: frame.minY + (target.minY - frame.minY) * amount,
                                  width: frame.width + (target.width - frame.width) * amount,
                                  height: frame.height + (target.height - frame.height) * amount), display: true)
        }
    }

    func stop() { timer?.invalidate(); timer = nil; target = nil }
}
