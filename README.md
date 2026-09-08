# Lully

A native macOS floating assistant with a compact React interface, Radix Themes controls, and bundled Plus Jakarta Sans. Ask questions, explicitly capture your screen, or transcribe microphone and computer audio for assistance.

## Install

Download the ZIP from this private repository’s Releases, extract it, and move **Lully.app** into Applications. The current release is for **Apple Silicon Macs running macOS 14 or later**. Builds use a persistent local development signature and are not notarized.

Open **Settings → Intelligence** and add your API key. Release downloads contain no API keys. OpenAI defaults to `gpt-realtime-2.1-mini`; Gemini and local Ollama are also supported. Model access and API billing belong to your provider account.

## Controls

- **Ask Lully:** sends your question and completed conversation history. It does not capture the screen.
- **Capture & ask:** captures your main display and sends the image and OCR with your question.
- **My Audio:** transcribes your microphone. **Media Audio:** transcribes computer sound. Selecting the other source switches listening; one source is active at a time.
- **Fresh chat:** clears conversation and capture context, cancels the answer, and stops listening. History otherwise remains for the current app session.
- **Capture protection:** requests exclusion from recordings. It can be turned off in General and resets to enabled on launch. Modern recorders may ignore it; universal invisibility is not guaranteed.
- **Window opacity:** adjust from 10–100% in General. The shortcut changes it by 10%; the setting persists across launches.
- **Light / Dark / System:** select a theme in General. Settings opens inside the overlay with Command–Comma.

| Action | Shortcut |
| --- | --- |
| Show / hide | Control–Option–Space |
| Pin / unpin | Control–Option–P |
| Capture & ask | Control–Option–S |
| Fresh chat | Control–Option–N |
| Focus Ask input | Control–Option–F |
| Window opacity | Control–Option–Plus / Minus |
| Move window | Control–Option–Arrow |
| Resize window, while Lully is focused | Command–Plus / Minus (Command–Equals also works) |
| Send | Enter or Command–Enter |
| New line | Shift–Enter |

Show/hide, pin, and capture shortcuts can be recorded in Settings → Shortcuts. Other shortcuts are fixed. Window movement and resizing stay within the display bounds.

## Audio and permissions

Enable Screen & System Audio Recording, Microphone, and Speech Recognition in macOS Privacy & Security as needed. Screen capture is manual. Audio transcription runs on-device in English; required language assets must be available. A transcription session may end automatically and need restarting.

The selected AI provider receives questions, supplied transcripts, and completed history. Screenshots are sent only on explicit capture. Opt-in audio auto-assist sends requests after a pause, and may make repeated billable calls. Hiding the panel does not stop listening.

## Build and run

Requires Xcode Command Line Tools, Node.js/npm, and Python 3.

```sh
./restart.sh
```

This builds the frontend and native app, quits Lully, installs the new copy into `/Applications`, and launches it. No local web server is needed. API keys entered in the app use macOS Keychain; protected key reads happen asynchronously.

A local-only `.local-secrets/openai.key` can optionally be included for personal builds. It is gitignored, extractable from such a build, and excluded from releases. Signing credentials stay outside the repository in the user’s Application Support directory. Set `LULLY_SIGNING_IDENTITY` to use your own signing identity.

## Verify and package

```sh
./check.sh
./release.sh
```

Checks cover provider protocols, Realtime events, explicit image input, history, interrupted-response recovery, shortcut validation, and window geometry. The build also validates TypeScript. `release.sh` excludes the bundled key and produces a ZIP and SHA-256 checksum in `releases/`. Run `./restart.sh` afterward to restore your personal installed build.

Live OpenAI smoke tests for arithmetic, image input, and follow-up context have passed. These are not broad accuracy or latency benchmarks. `Lully.app/Contents/MacOS/Lully --test-openai` runs those API-backed checks with the configured key.

Chat history is not persisted across app restarts. Extended audio transcription and recording exclusion should be tested with your actual setup.
