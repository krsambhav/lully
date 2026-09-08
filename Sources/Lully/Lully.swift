import Combine
import AppKit
import Carbon
import WebKit

@MainActor final class LullyState: ObservableObject {
    @Published var theme = UserDefaults.standard.string(forKey: "theme") ?? "system"
    @Published var opacity = min(1.0, max(0.3, UserDefaults.standard.object(forKey: "opacity") as? Double ?? 1.0))
    @Published var captureProtection = true
    @Published var screenAccess = CGPreflightScreenCaptureAccess()
    @Published var turns: [ConversationTurn] = []
    private var sessionGeneration = UUID()
    var chatSession: String { sessionGeneration.uuidString }
    @Published var pinned = UserDefaults.standard.object(forKey: "pinned") as? Bool ?? true
    @Published var provider = Provider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .openai
    @Published var apiKey = ""
    @Published var keySaved = false
    @Published var deep = false
    @Published var firstToken: Double?
    private var screenJPEG: Data?
    @Published var prompt = ""
    @Published var answer = ""
    @Published var screen = ""
    @Published var transcript = ""
    @Published var error = ""
    @Published var listening = false
    @Published var audioBusy = false
    @Published var reading = false
    @Published var thinking = false
    @Published var settings = false
    @Published var focusRequest = 0
    @Published var showContext = false
    @Published var systemAudio = false
    @Published var autoAssist = false
    @Published var screenTime: Date?
    @Published var endpoint = UserDefaults.standard.string(forKey: "endpoint") ?? "http://127.0.0.1:11434"
    @Published var model = UserDefaults.standard.string(forKey: "model") ?? Provider.openai.defaultModel
    private let audio = AudioListener()
    private var audioGeneration = UUID()
    private var answerTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var pendingTranscript = ""

    func changeProvider() {
        model = provider.defaultModel
        apiKey = ""
        keySaved = KeyStore.contains(provider)
    }

    func saveKey() {
        do {
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try KeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), provider: provider)
            apiKey = ""
            keySaved = true
            error = ""
        } catch { self.error = error.localizedDescription }
    }

    func removeKey() {
        do { try KeyStore.delete(provider); apiKey = ""; keySaved = false }
        catch { self.error = error.localizedDescription }
    }

    func saveSettings() {
        UserDefaults.standard.set(theme, forKey: "theme")
        UserDefaults.standard.set(provider.rawValue, forKey: "provider")
        UserDefaults.standard.set(endpoint, forKey: "endpoint")
        UserDefaults.standard.set(model, forKey: "model")
    }

    func refreshScreenAccess() { screenAccess = CGPreflightScreenCaptureAccess() }

    func readScreen() async {
        refreshScreenAccess()
        guard !reading else { return }
        let session = sessionGeneration
        reading = true
        error = ""
        defer { if session == sessionGeneration { reading = false } }
        do {
            let text = try await ScreenReader.read()
            guard session == sessionGeneration, !Task.isCancelled else { return }
            screen = text.text
            screenJPEG = text.jpeg
            screenTime = Date()
            if text.text.isEmpty && provider == .ollama { error = "No readable text found. Local mode uses OCR; cloud mode can also interpret the screenshot." }
        } catch {
            guard session == sessionGeneration else { return }
            screen = ""
            screenTime = nil
            screenJPEG = nil
            self.error = "Screen read failed: \(error.localizedDescription) Check Screen Recording permission in System Settings."
        }
    }

    func toggleAudio(systemAudio requestedSource: Bool? = nil) {
        guard !audioBusy else { return }
        let target = requestedSource ?? systemAudio
        let stopping = listening && target == systemAudio
        let session = sessionGeneration
        systemAudio = target
        audioBusy = true
        Task { [self] in
            if listening {
                audioGeneration = UUID()
                listening = false
                automaticTask?.cancel()
                await audio.stop()
            }
            guard session == sessionGeneration else { return }
            if !stopping {
                error = ""
                pendingTranscript = transcript.isEmpty ? "" : transcript + "\n\n"
                let generation = UUID()
                audioGeneration = generation
                do {
                    try await audio.start(systemAudio: systemAudio, update: { [weak self] text in
                        Task { @MainActor in
                            guard let self, self.audioGeneration == generation else { return }
                            self.transcript = String((self.pendingTranscript + text).suffix(40000))
                            self.scheduleAutomaticAnswer()
                        }
                    }, failed: { [weak self] message in
                        Task { @MainActor in
                            guard let self, self.audioGeneration == generation else { return }
                            self.audioGeneration = UUID()
                            self.listening = false
                            self.error = message
                            self.automaticTask?.cancel()
                            await self.audio.stop()
                        }
                    })
                    if audioGeneration == generation { listening = true } else { await audio.stop() }
                } catch { if audioGeneration == generation { self.error = error.localizedDescription } }
            }
            audioBusy = false
        }
    }

    private func scheduleAutomaticAnswer() {
        automaticTask?.cancel()
        guard autoAssist, listening else { return }
        automaticTask = Task {
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            guard autoAssist, listening, !thinking else { return }
            ask(automatic: true)
        }
    }

    func ask(automatic: Bool = false, captureScreen: Bool = false) {
        guard !thinking, !reading else { return }
        saveSettings()
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            settings = true
            error = "Enter a model ID in Settings to enable answers."
            return
        }
        let chosenProvider = provider
        let chosenModel = model
        let chosenEndpoint = endpoint
        let useDeep = deep
        let useScreen = captureScreen
        thinking = true
        firstToken = nil
        error = ""
        answer = ""
        let question = automatic ? "Answer the latest question or explain the latest issue in the audio. If no assistance is needed, say so briefly." : (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Help me with the supplied conversation or question. If there is not enough context, ask a short clarifying question." : prompt)
        let session = sessionGeneration
        let history = ConversationContext.messages(from: turns)
        let turn = ConversationTurn(question: question)
        turns.append(turn)
        answerTask = Task { [self] in
            defer {
                if session == sessionGeneration {
                    thinking = false
                    if let index = turns.firstIndex(where: { $0.id == turn.id }) {
                        turns[index].pending = false
                        if turns[index].answer.isEmpty { turns[index].issue = error.isEmpty ? "Response stopped." : error }
                    }
                }
            }
            let key = chosenProvider == .ollama ? "" : await Task.detached { KeyStore.read(chosenProvider) }.value
            guard !Task.isCancelled, session == sessionGeneration else { return }
            guard chosenProvider == .ollama || !key.isEmpty else {
                settings = true
                error = "Add your \(chosenProvider.rawValue) API key in Settings."
                return
            }
            if useScreen {
                await readScreen()
                guard screenTime != nil, session == sessionGeneration else { return }
            }
            if let index = turns.firstIndex(where: { $0.id == turn.id }) {
                turns[index].context = (useScreen ? "\nCaptured screen text:\n" + String(screen.prefix(18000)) : "") + (transcript.isEmpty ? "" : "\nAudio transcript:\n" + String(transcript.suffix(18000)))
            }
            do {
                try Task.checkCancellation()
                let started = Date()
                let update: @MainActor (String) -> Void = { [weak self] text in
                    guard let self, session == self.sessionGeneration else { return }
                    if self.firstToken == nil && !text.isEmpty { self.firstToken = Date().timeIntervalSince(started) }
                    self.answer = text
                    if let index = self.turns.firstIndex(where: { $0.id == turn.id }) {
                        self.turns[index].answer = text
                        self.turns[index].firstToken = self.firstToken
                    }
                }
                if chosenProvider == .ollama {
                    try await Assistant.answer(endpoint: chosenEndpoint, model: chosenModel, prompt: question, screen: useScreen ? screen : "", transcript: transcript, history: history, update: update)
                } else {
                    try await CloudAssistant.answer(provider: chosenProvider, model: chosenModel, key: key, deep: useDeep, prompt: question, screen: useScreen ? screen : "", jpeg: useScreen ? screenJPEG : nil, transcript: transcript, history: history, update: update)
                }
            } catch is CancellationError {
            } catch let failure as URLError where failure.code == .cancelled {
            } catch {
                if session == sessionGeneration {
                    self.error = error.localizedDescription
                    if let index = turns.firstIndex(where: { $0.id == turn.id }) { turns[index].issue = error.localizedDescription }
                }
            }
        }
    }

    func cancelAnswer() { answerTask?.cancel() }

    func clear() {
        sessionGeneration = UUID()
        audioGeneration = UUID()
        answerTask?.cancel()
        automaticTask?.cancel()
        turns = []
        thinking = false
        reading = false
        listening = false
        autoAssist = false
        screenJPEG = nil; screen = ""; transcript = ""; pendingTranscript = ""
        answer = ""; prompt = ""; error = ""; screenTime = nil; firstToken = nil
        audioBusy = true
        Task { await audio.stop(); audioBusy = false }
    }

}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = LullyState()
    var panel: OverlayPanel!
    var statusItem: NSStatusItem!
    let shortcuts = ShortcutManager()
    var webBridge: PanelBridge!
    let mover = WindowMover()
    let resizer = WindowResizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = OverlayPanel(contentRect: NSRect(x: 100, y: 180, width: 480, height: 680), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        mover.panel = panel
        applyTheme()
        panel.alphaValue = state.opacity
        panel.title = "Lully"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = state.pinned ? .floating : .normal
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Best-effort legacy protection. ScreenCaptureKit recorders may ignore this.
        applyCaptureProtection()
        webBridge = PanelBridge(state: state, host: self)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = PanelContainerView(webView: webBridge.webView)
        panel.minSize = NSSize(width: 420, height: 560)
        panel.setFrameAutosaveName("LullyOverlayV2")
        panel.makeKeyAndOrderFront(nil)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "Lully")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide Lully", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Pin / Unpin window", action: #selector(togglePin), keyEquivalent: "")
        menu.addItem(withTitle: "Capture screen & assist", action: #selector(captureAssist), keyEquivalent: "")
        menu.addItem(withTitle: "Assist with current context", action: #selector(assist), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lully", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = menu.copy() as? NSMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        state.keySaved = KeyStore.contains(state.provider)
        shortcuts.onAction = { [weak self] action in
            if action >= 10 {
                guard let self else { return }
                self.setOpacity(self.state.opacity + ([10, 12, 13].contains(action) ? 0.05 : -0.05))
            } else if action == 9 { self?.focusInput() } else if action == 8 { self?.freshChat() } else if action == 1 { self?.toggle() } else if action == 2 { self?.togglePin() } else { self?.captureAssist() }
        }
        shortcuts.onMovement = { [weak self] direction, pressed in self?.mover.key(direction, pressed: pressed) }
        do { try shortcuts.start() } catch { state.error = error.localizedDescription }
        resizer.start(panel: panel) { [weak self] in self?.webBridge.isRecordingShortcut == false }
        webBridge.load()

    }

    func setOpacity(_ value: Double) {
        guard value.isFinite else { return }
        state.opacity = min(1, max(0.3, (value * 100).rounded() / 100))
        panel.alphaValue = state.opacity
        UserDefaults.standard.set(state.opacity, forKey: "opacity")
        webBridge.sendState()
    }

    func applyCaptureProtection() {
        panel.sharingType = state.captureProtection ? .none : .readOnly
    }

    func applyTheme() {
        panel?.appearance = state.theme == "dark" ? NSAppearance(named: .darkAqua) : state.theme == "light" ? NSAppearance(named: .aqua) : nil
    }

    @objc func openSettings() {
        state.settings = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webBridge.sendState()
    }

    @objc func togglePin() {
        state.pinned.toggle()
        panel.level = state.pinned ? .floating : .normal
        panel.isFloatingPanel = state.pinned
        UserDefaults.standard.set(state.pinned, forKey: "pinned")
        webBridge.sendState()
    }

    func applicationDidBecomeActive(_ notification: Notification) { state.refreshScreenAccess() }

    @objc func toggle() {
        mover.stop()
        resizer.stop()
        if panel.isVisible { panel.orderOut(nil) }
        else { panel.makeKeyAndOrderFront(nil) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.makeKeyAndOrderFront(nil)
        return true
    }
    @objc func focusInput() {
        state.settings = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        state.focusRequest += 1
        webBridge.sendState()
    }

    @objc func freshChat() {
        state.clear()
        state.settings = false
        webBridge.sendState()
    }

    @objc func captureAssist() {
        panel.makeKeyAndOrderFront(nil)
        state.prompt = "Help me with this screen."
        state.ask(captureScreen: true)
    }
    @objc func assist() { panel.makeKeyAndOrderFront(nil); state.ask() }
    @objc func quit() { NSApp.terminate(nil) }
}

@main enum LullyApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--import-gemini-key") {
            do {
                guard let key = readLine(), !key.isEmpty else { throw LullyError(message: "No key provided on stdin.") }
                try KeyStore.save(key, provider: .gemini)
                print("Gemini key saved to macOS Keychain.")
                exit(0)
            } catch { print(error.localizedDescription); exit(1) }
        }
        if CommandLine.arguments.contains("--test-gemini") || CommandLine.arguments.contains("--test-openai") {
            let provider: Provider = CommandLine.arguments.contains("--test-openai") ? .openai : .gemini
            Task {
                let started = Date()
                var first: Double?
                var received = ""
                do {
                    try await CloudAssistant.answer(provider: provider, model: provider.defaultModel, key: KeyStore.read(provider), deep: false, prompt: "Reply with only the answer: 2 + 2", screen: "", jpeg: nil, transcript: "") { text in
                        received = text
                        if first == nil && !text.isEmpty { first = Date().timeIntervalSince(started) }
                    }
                    guard received.trimmingCharacters(in: .whitespacesAndNewlines).contains("4") else { throw LullyError(message: "Arithmetic smoke test returned an unexpected answer.") }
                    if provider == .openai {
                        let image = NSImage(size: NSSize(width: 32, height: 32))
                        image.lockFocus()
                        NSColor.red.setFill()
                        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
                        image.unlockFocus()
                        let jpeg = image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .jpeg, properties: [:]) }
                        guard let jpeg else { throw LullyError(message: "Could not create test image.") }
                        received = ""
                        try await CloudAssistant.answer(provider: .openai, model: provider.defaultModel, key: KeyStore.read(.openai), deep: false, prompt: "What is the remembered code and the solid color of this image? Reply with only both values.", screen: "", jpeg: jpeg, transcript: "", history: [ChatMessage(role: "user", content: "Remember the code LULLY-17."), ChatMessage(role: "assistant", content: "LULLY-17")]) { received = $0 }
                        guard received.contains("LULLY-17"), received.lowercased().contains("red") else { throw LullyError(message: "Image and follow-up smoke test returned an unexpected answer.") }
                        print("Image and follow-up context checks passed.")
                    }
                    print(String(format: "Streaming passed. First text: %.2fs. Completed: %.2fs.", first ?? -1, Date().timeIntervalSince(started)))
                    exit(0)
                } catch { print("Streaming failed: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
