import AppKit
import Carbon

struct ShortcutSpec: Codable, Equatable {
    var key: String
    var command: Bool
    var option: Bool
    var control: Bool
    var shift: Bool

    static let hideDefault = ShortcutSpec(key: "Space", command: false, option: true, control: true, shift: false)
    static let captureDefault = ShortcutSpec(key: "KeyS", command: false, option: true, control: true, shift: false)
    static let pinDefault = ShortcutSpec(key: "KeyP", command: false, option: true, control: true, shift: false)
    static let codes: [String: UInt32] = ["KeyA":0,"KeyS":1,"KeyD":2,"KeyF":3,"KeyH":4,"KeyG":5,"KeyZ":6,"KeyX":7,"KeyC":8,"KeyV":9,"KeyB":11,"KeyQ":12,"KeyW":13,"KeyE":14,"KeyR":15,"KeyY":16,"KeyT":17,"Digit1":18,"Digit2":19,"Digit3":20,"Digit4":21,"Digit6":22,"Digit5":23,"Digit9":25,"Digit7":26,"Digit8":28,"Digit0":29,"KeyO":31,"KeyU":32,"KeyI":34,"KeyP":35,"KeyL":37,"KeyJ":38,"KeyK":40,"KeyN":45,"KeyM":46,"Space":49,"F1":122,"F2":120,"F3":99,"F4":118,"F5":96,"F6":97,"F7":98,"F8":100,"F9":101,"F10":109,"F11":103,"F12":111]
    var valid: Bool { Self.codes[key] != nil && (command || option || control) }
    var modifiers: UInt32 { (command ? UInt32(cmdKey) : 0) | (option ? UInt32(optionKey) : 0) | (control ? UInt32(controlKey) : 0) | (shift ? UInt32(shiftKey) : 0) }
    var label: String { (control ? "⌃ " : "") + (option ? "⌥ " : "") + (shift ? "⇧ " : "") + (command ? "⌘ " : "") + key.replacingOccurrences(of: "Key", with: "").replacingOccurrences(of: "Digit", with: "") }
}

@MainActor final class ShortcutManager {
    private(set) var hide: ShortcutSpec
    private(set) var pin: ShortcutSpec
    private(set) var capture: ShortcutSpec
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onAction: ((UInt32) -> Void)?
    var onMovement: ((UInt32, Bool) -> Void)?

    init() {
        let defaults = UserDefaults.standard
        hide = defaults.data(forKey: "shortcut.hide").flatMap { try? JSONDecoder().decode(ShortcutSpec.self, from: $0) } ?? .hideDefault
        capture = defaults.data(forKey: "shortcut.capture").flatMap { try? JSONDecoder().decode(ShortcutSpec.self, from: $0) } ?? .captureDefault
        pin = defaults.data(forKey: "shortcut.pin").flatMap { try? JSONDecoder().decode(ShortcutSpec.self, from: $0) } ?? .pinDefault
    }

    func start() throws {
        if handler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
                guard let event, let data else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr else { return status }
                let manager = Unmanaged<ShortcutManager>.fromOpaque(data).takeUnretainedValue()
                let action = id.id
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                Task { @MainActor in
                    if (4...7).contains(action) { manager.onMovement?(action, pressed) }
                    else if pressed { manager.onAction?(action) }
                }
                return noErr
            }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw LullyError(message: "Could not enable global shortcuts. Use the panel or menu bar controls.") }
        }
        try register(hide: hide, pin: pin, capture: capture)
    }

    func suspend() { refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); for id in UInt32(4)...7 { onMovement?(id, false) } }
    func resume() throws { try register(hide: hide, pin: pin, capture: capture) }

    private func register(hide: ShortcutSpec, pin: ShortcutSpec, capture: ShortcutSpec) throws {
        guard hide.valid, pin.valid, capture.valid else { throw LullyError(message: "Use ⌘, ⌥, or ⌃ with a letter, number, Space, or F1–F12.") }
        guard hide != pin, hide != capture, pin != capture else { throw LullyError(message: "Each action needs a different shortcut.") }
        suspend()
        for (index, spec) in [hide, pin, capture].enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(ShortcutSpec.codes[spec.key]!, spec.modifiers, EventHotKeyID(signature: 0x4C554C59, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                suspend()
                throw LullyError(message: "\(spec.label) is unavailable or used by another app. Choose another combination.")
            }
            refs.append(ref)
        }
        for (index, code) in [UInt32(123), 124, 126, 125, 45, 3].enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(code, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x4C554C59, id: UInt32(index + 4)), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                suspend()
                throw LullyError(message: index == 5 ? "Control–Option–F is unavailable. It is reserved for focusing Lully." : index == 4 ? "Control–Option–N is unavailable. It is reserved for Fresh chat." : "Control–Option–Arrow is unavailable. It is reserved for window movement.")
            }
            refs.append(ref)
        }
        let opacityKeys: [(UInt32, UInt32, UInt32)] = [
            (10, 24, 0), (11, 27, 0), (12, 24, UInt32(shiftKey)),
            (13, 69, 0), (14, 78, 0)
        ]
        for (id, code, extraModifiers) in opacityKeys {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(code, UInt32(controlKey | optionKey) | extraModifiers, EventHotKeyID(signature: 0x4C554C59, id: id), GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                suspend()
                throw LullyError(message: "Control–Option–Plus/Minus is unavailable. It is reserved for window opacity.")
            }
            refs.append(ref)
        }
    }

    func update(action: String, spec: ShortcutSpec) throws {
        let nextHide = action == "hide" ? spec : hide
        let nextPin = action == "pin" ? spec : pin
        let nextCapture = action == "capture" ? spec : capture
        do { try register(hide: nextHide, pin: nextPin, capture: nextCapture) }
        catch { try? register(hide: hide, pin: pin, capture: capture); throw error }
        hide = nextHide; pin = nextPin; capture = nextCapture
        UserDefaults.standard.set(try JSONEncoder().encode(hide), forKey: "shortcut.hide")
        UserDefaults.standard.set(try JSONEncoder().encode(pin), forKey: "shortcut.pin")
        UserDefaults.standard.set(try JSONEncoder().encode(capture), forKey: "shortcut.capture")
    }
}
