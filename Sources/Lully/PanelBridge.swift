import AppKit
import WebKit
import Combine

final class LullyWebView: WKWebView {
    // The first click should focus the intended control, including when the app is inactive.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class PanelBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private let state: LullyState
    private weak var host: AppDelegate?
    private var updates: AnyCancellable?
    private var loaded = false
    private var recordingTarget: String?
    var isRecordingShortcut: Bool { recordingTarget != nil }
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var resourceURL: URL?

    init(state: LullyState, host: AppDelegate) {
        self.state = state
        self.host = host
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = LullyWebView(frame: .zero, configuration: config)
        webView.focusRingType = .none
        super.init()
        config.userContentController.add(self, name: "lully")
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = NSColor(red: 0.09, green: 0.10, blue: 0.098, alpha: 1)
        updates = state.objectWillChange.throttle(for: .milliseconds(60), scheduler: RunLoop.main, latest: true).sink { [weak self] in
            DispatchQueue.main.async { self?.sendState() }
        }
    }

    func load() {
        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("UI"), FileManager.default.fileExists(atPath: resources.appendingPathComponent("index.html").path) else {
            webView.loadHTMLString("<html><body style='background:#181b19;color:#eceeec;font:16px system-ui;padding:32px'>Lully's interface is missing. Run build.sh to rebuild the app.</body></html>", baseURL: nil)
            return
        }
        resourceURL = resources.appendingPathComponent("index.html")
        webView.loadFileURL(resourceURL!, allowingReadAccessTo: resources)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.isFileURL == true && navigationAction.request.url?.standardizedFileURL.path == resourceURL?.standardizedFileURL.path ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // React's ready message can arrive after WebKit's document-finished event.
        // Do not replace the document while React is still mounting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.loaded else { return }
            self.webView.evaluateJavaScript("typeof window.lullyReceive === 'function'") { [weak self] result, _ in
                guard let self else { return }
                if result as? Bool == true { self.loaded = true; self.sendState() }
                else { self.webView.evaluateJavaScript("document.body.textContent = 'Lully could not load its interface. Quit the app and run build.sh to rebuild its bundled UI.'", completionHandler: nil) }
            }
        }
    }

    func sendState() {
        guard loaded, let host else { return }
        let snapshot: [String: Any] = [
            "opacity": state.opacity, "captureProtection": state.captureProtection, "theme": state.theme, "screenAccess": state.screenAccess, "provider": state.provider.rawValue, "model": state.model, "endpoint": state.endpoint,
            "bundledKey": !KeyStore.bundledKey(state.provider).isEmpty, "keySaved": state.keySaved, "deep": state.deep, "pinned": state.pinned,
            "recordingShortcut": recordingTarget.map { $0 as Any } ?? NSNull(),
            "focusRequest": state.focusRequest, "chatSession": state.chatSession, "turns": state.turns.map { turn in ["id": turn.id.uuidString, "question": turn.question, "answer": turn.answer, "pending": turn.pending, "issue": turn.issue, "firstToken": turn.firstToken.map { $0 as Any } ?? NSNull()] as [String: Any] },
            "answer": state.answer, "screen": state.screen, "transcript": state.transcript,
            "error": state.error, "listening": state.listening, "audioBusy": state.audioBusy,
            "reading": state.reading, "thinking": state.thinking, "settings": state.settings,
            "systemAudio": state.systemAudio, "autoAssist": state.autoAssist,
            "firstToken": state.firstToken.map { $0 as Any } ?? NSNull(),
            "screenTime": state.screenTime.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "hideShortcut": host.shortcuts.hide.label, "pinShortcut": host.shortcuts.pin.label, "captureShortcut": host.shortcuts.capture.label, "prompt": state.prompt,
            "native": true
        ]
        webView.callAsyncJavaScript("window.lullyReceive?.(snapshot)", arguments: ["snapshot": snapshot], in: nil, in: .page) { _ in }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true, message.frameInfo.request.url?.standardizedFileURL.path == resourceURL?.standardizedFileURL.path,
              let body = message.body as? [String: Any], let action = body["action"] as? String, let host else { return }
        switch action {
        case "ready": loaded = true
        case "ask":
            state.prompt = body["prompt"] as? String ?? ""
            state.ask()
        case "capture":
            state.prompt = body["prompt"] as? String ?? "Help me with this screen."
            state.ask(captureScreen: true)
        case "screenSettings":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        case "refreshScreenAccess": state.refreshScreenAccess()
        case "cancel": state.cancelAnswer()
        case "read": host.captureAssist()
        case "listen": state.toggleAudio(systemAudio: body["systemAudio"] as? Bool)
        case "pin": host.togglePin()
        case "hide":
            resumeShortcuts()
            host.mover.stop()
            host.panel.orderOut(nil)
        case "drag":
            if let event = NSApp.currentEvent, event.type == .leftMouseDown { host.panel.performDrag(with: event) }
        case "settings":
            if body["open"] as? Bool != true { resumeShortcuts() }
            state.settings = body["open"] as? Bool ?? false
        case "saveKey": state.apiKey = body["key"] as? String ?? ""; state.saveKey()
        case "removeKey": state.removeKey()
        case "clear": state.clear()
        case "dismissError": state.error = ""
        case "copy":
            let text = (body["id"] as? String).flatMap { id in state.turns.first(where: { $0.id.uuidString == id })?.answer } ?? state.answer
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        case "configure":
            if let opacity = body["opacity"] as? Double { host.setOpacity(opacity) }
            if let enabled = body["captureProtection"] as? Bool { state.captureProtection = enabled; host.applyCaptureProtection() }
            if let theme = body["theme"] as? String, ["light", "dark", "system"].contains(theme) { state.theme = theme; host.applyTheme() }
            if let provider = body["provider"] as? String, let value = Provider(rawValue: provider), value != state.provider { state.provider = value; state.changeProvider() }
            if let model = body["model"] as? String { state.model = String(model.prefix(120)) }
            if let endpoint = body["endpoint"] as? String { state.endpoint = String(endpoint.prefix(300)) }
            if let deep = body["deep"] as? Bool { state.deep = deep }
            if let value = body["autoAssist"] as? Bool { state.autoAssist = value }
            if let value = body["systemAudio"] as? Bool, !state.listening, !state.audioBusy { state.systemAudio = value }
            state.saveSettings()
        case "recordShortcut":
            if let target = body["target"] as? String, ["hide", "pin", "capture"].contains(target) { beginRecording(target) }
        case "cancelShortcut": resumeShortcuts()
        case "resetShortcut":
            guard let target = body["target"] as? String, ["hide", "pin", "capture"].contains(target) else { return }
            do { try host.shortcuts.update(action: target, spec: target == "hide" ? .hideDefault : target == "pin" ? .pinDefault : .captureDefault); state.error = "" }
            catch { state.error = error.localizedDescription }
        default: return
        }
        sendState()
    }

    private func beginRecording(_ target: String) {
        resumeShortcuts()
        guard let host else { return }
        host.shortcuts.suspend()
        recordingTarget = target
        state.error = ""
        NSApp.activate(ignoringOtherApps: true)
        host.panel.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let target = self.recordingTarget, let host = self.host else { return event }
            if event.keyCode == 53 { self.resumeShortcuts(); self.sendState(); return nil }
            guard let key = ShortcutSpec.codes.first(where: { $0.value == UInt32(event.keyCode) })?.key else {
                self.state.error = "Use a letter, number, Space, or F1–F12. Press Esc to cancel."
                self.sendState(); return nil
            }
            let flags = event.modifierFlags
            let spec = ShortcutSpec(key: key, command: flags.contains(.command), option: flags.contains(.option), control: flags.contains(.control), shift: flags.contains(.shift))
            do {
                try host.shortcuts.update(action: target, spec: spec)
                self.stopRecording()
                self.state.error = ""
            } catch {
                host.shortcuts.suspend()
                self.state.error = error.localizedDescription
            }
            self.sendState()
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: host.panel, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeShortcuts(); self?.sendState() }
        }
        sendState()
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        resignObserver = nil
        recordingTarget = nil
    }

    private func resumeShortcuts() {
        guard recordingTarget != nil else { return }
        stopRecording()
        do { try host?.shortcuts.resume() } catch { state.error = error.localizedDescription }
    }
}
