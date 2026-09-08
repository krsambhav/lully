# Lully project instructions

- After finishing each app task, quit the existing Lully process and launch the newly built app. Verify the packaged native UI, not only the browser preview.
- Use Plus Jakarta Sans, bundled locally. UI controls use Radix Themes. Keep the interface compact and polished.
- Screen capture must be explicit: only Capture & ask and its configurable shortcut may capture/send a new screenshot. Ordinary questions and audio auto-assist must not read the screen.
- Keep separate configurable global shortcuts for show/hide, pin/unpin (always on top), and capture/assist. Persist settings and reject conflicts.
- Never put API keys in code, preferences, documentation, or logs. Use macOS Keychain. Do not synchronously read protected key data on UI startup.
- Screen recording exclusion is best-effort; do not claim universal invisibility.
- Preserve all chat turns in the current session and include completed turns in follow-up model requests. Fresh chat is the explicit control to cancel work and clear conversation/capture context.
- Record configurable shortcuts with native NSEvent handling, not embedded-browser key events. Verify actual key recording and persistence in the packaged app.
