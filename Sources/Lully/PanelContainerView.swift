import AppKit
import WebKit

final class PanelDragHandle: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class PanelResizeHandle: NSView {
    var onStart: (() -> Void)?
    private let edge: CGFloat = 7
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func directions(_ point: NSPoint) -> (Int, Int) {
        let horizontal = point.x < edge ? -1 : point.x >= bounds.width - edge ? 1 : 0
        let vertical = point.y < edge ? -1 : point.y >= bounds.height - edge ? 1 : 0
        return (horizontal, vertical)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let (x, y) = directions(local)
        return x != 0 || y != 0 ? self : nil
    }
    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: 0, width: edge, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - edge, y: 0, width: edge, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: edge, y: 0, width: max(0, bounds.width - 2 * edge), height: edge), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: edge, y: bounds.height - edge, width: max(0, bounds.width - 2 * edge), height: edge), cursor: .resizeUpDown)
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onStart?()
        let (horizontal, vertical) = directions(convert(event.locationInWindow, from: nil))
        let start = window.convertPoint(toScreen: event.locationInWindow)
        let frame = window.frame
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let current = window.convertPoint(toScreen: next.locationInWindow)
            window.setFrame(WindowResize.dragged(frame, dx: current.x - start.x, dy: current.y - start.y,
                                                 horizontal: horizontal, vertical: vertical, minimum: window.minSize), display: true)
        }
        window.saveFrame(usingName: "LullyOverlayV2")
    }
}

final class PanelContainerView: NSView {
    private let webView: WKWebView
    private let dragHandle = PanelDragHandle()
    private let resizeHandle = PanelResizeHandle()

    init(webView: WKWebView, onResize: @escaping () -> Void) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(webView)
        addSubview(dragHandle)
        resizeHandle.onStart = onResize
        addSubview(resizeHandle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        webView.frame = bounds
        resizeHandle.frame = bounds
        window?.invalidateCursorRects(for: resizeHandle)
        dragHandle.frame = NSRect(x: 0, y: bounds.height - 36, width: 110, height: 36)
    }
}
