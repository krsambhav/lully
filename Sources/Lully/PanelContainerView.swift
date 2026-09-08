import AppKit
import WebKit

final class PanelDragHandle: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class PanelContainerView: NSView {
    private let webView: WKWebView
    private let dragHandle = PanelDragHandle()

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(webView)
        addSubview(dragHandle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        webView.frame = bounds
        dragHandle.frame = NSRect(x: 0, y: bounds.height - 50, width: 140, height: 50)
    }
}
