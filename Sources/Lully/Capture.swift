import AppKit
import ScreenCaptureKit
import Vision
import Speech
import AVFoundation

struct LullyError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ScreenSnapshot {
    let text: String
    let jpeg: Data?
}

enum ScreenReader {
    static func requirePermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw LullyError(message: "Screen access is not active for this installed copy of Lully. Open Settings → General → Screen access. If Lully is already enabled in macOS, turn it off and on, then quit and reopen Lully. If that does not help, remove the old entry and add /Applications/Lully.app again.")
        }
    }
    static func filter() async throws -> (SCContentFilter, SCDisplay) {
        try requirePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw LullyError(message: "No display is available. Check Screen Recording access in System Settings.")
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        return (SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: []), display)
    }

    static func read() async throws -> ScreenSnapshot {
        let (filter, display) = try await filter()
        let config = SCStreamConfiguration()
        let scale = min(1.0, 1920.0 / Double(display.width))
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.75])
            return ScreenSnapshot(text: text, jpeg: jpeg)
        }.value
    }
}

final class AudioListener: NSObject, SCStreamOutput, SCStreamDelegate {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var engine: AVAudioEngine?
    private var stream: SCStream?
    private var onFailure: ((String) -> Void)?

    func start(systemAudio: Bool, update: @escaping (String) -> Void, failed: @escaping (String) -> Void) async throws {
        if systemAudio { try ScreenReader.requirePermission() }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized else {
            throw LullyError(message: "Allow Speech Recognition for Lully in System Settings → Privacy & Security.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            throw LullyError(message: "English speech recognition is unavailable on this Mac.")
        }
        let speech = SFSpeechAudioBufferRecognitionRequest()
        speech.shouldReportPartialResults = true
        // Do not silently send captured conversation audio to a remote speech service.
        guard recognizer.supportsOnDeviceRecognition else {
            throw LullyError(message: "On-device English recognition is unavailable. Enable/download English Dictation in macOS settings.")
        }
        speech.requiresOnDeviceRecognition = true
        setRequest(speech)
        onFailure = failed
        recognition = recognizer.recognitionTask(with: speech) { result, error in
            if let result { update(result.bestTranscription.formattedString) }
            if let error { failed(error.localizedDescription) }
            else if result?.isFinal == true { failed("Speech recognition finished. Start listening again to continue.") }
        }
        do {
            if systemAudio {
                let (filter, _) = try await ScreenReader.filter()
                let config = SCStreamConfiguration()
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 16000
                config.channelCount = 1
                let capture = SCStream(filter: filter, configuration: config, delegate: self)
                try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "lully.audio"))
                // Drain screen frames even though only audio is retained.
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "lully.frames"))
                stream = capture
                try await capture.startCapture()
            } else {
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard allowed else { throw LullyError(message: "Allow Microphone access for Lully in System Settings.") }
                let audio = AVAudioEngine()
                let input = audio.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { throw LullyError(message: "No usable microphone is connected.") }
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    self?.lock.lock()
                    self?.request?.append(buffer)
                    self?.lock.unlock()
                }
                engine = audio
                audio.prepare()
                try audio.start()
            }
        } catch {
            await stop()
            throw error
        }
    }

    private func setRequest(_ value: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = value
        lock.unlock()
    }

    func stop() async {
        let oldStream = stream
        stream = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        setRequest(nil)
        recognition?.cancel()
        recognition = nil
        onFailure = nil
        if let oldStream { try? await oldStream.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        lock.lock()
        request?.appendAudioSampleBuffer(sampleBuffer)
        lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure?(error.localizedDescription) }
}
