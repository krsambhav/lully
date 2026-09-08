# Lully — desktop copilot

## Purpose

Live on the user's screen as a floating assistant, read on-screen information, transcribe audio, and answer or help solve the current task. The requested recording-invisibility behavior is a critical compatibility requirement, not a verified capability.

## Current implementation

- Native macOS panel, menu bar controls, global show/hide shortcut.
- Best-effort window capture protection, with its limitation disclosed in the panel.
- Main-display screen capture, local OCR, screenshot input for cloud models.
- Microphone or system-audio transcription using on-device English speech recognition.
- Manual assistance and opt-in assistance after an audio pause.
- OpenAI GPT-Realtime-2.1 Mini by default over WebSocket, optional Gemini or local Ollama.
- Fast/deep response styles, editable models, Keychain credentials, in-memory chat history.

## Release gates

- Test real audio and screen capture after the user grants macOS permissions.
- Verify recording visibility against the user's actual recording/sharing software. Modern ScreenCaptureKit may ignore the window sharing flag; universal invisibility is not supported by this implementation.
- Evaluate latency and accuracy on representative screen and audio questions. A successful tiny arithmetic request does not establish production performance.
- Validate extended transcription, resource cleanup, and restart behavior under prolonged use.
- Sign and notarize a distribution build before wider release.
