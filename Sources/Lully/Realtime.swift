import Foundation

/// Text answers over Realtime; capture and on-device speech remain explicitly controlled by the user.
enum RealtimeAssistant {
    static func events(prompt: String, screen: String, jpeg: Data?, transcript: String, history: [ChatMessage], deep: Bool) -> [[String: Any]] {
        let instructions = CloudAssistant.instructions + (deep ? " Check your answer carefully and explain the important steps." : " Keep the answer brief and direct.")
        var events: [[String: Any]] = [["type": "session.update", "session": ["type": "realtime", "output_modalities": ["text"], "instructions": instructions, "max_output_tokens": 8192]]]
        for message in history {
            events.append(["type": "conversation.item.create", "item": ["type": "message", "role": message.role, "content": [["type": message.role == "assistant" ? "output_text" : "input_text", "text": message.content]]]])
        }
        let context = "SCREEN OCR:\n<screen>\n\(screen.prefix(18000))\n</screen>\nAUDIO TRANSCRIPT:\n<audio>\n\(transcript.suffix(18000))\n</audio>\nUSER REQUEST:\n\(prompt)"
        var content: [[String: Any]] = [["type": "input_text", "text": context]]
        if let jpeg { content.append(["type": "input_image", "image_url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]) }
        events.append(["type": "conversation.item.create", "item": ["type": "message", "role": "user", "content": content]])
        events.append(["type": "response.create", "response": ["output_modalities": ["text"]]])
        return events
    }

    static func parse(_ json: [String: Any]) throws -> StreamDelta {
        let type = json["type"] as? String ?? ""
        if type == "error" {
            let error = json["error"] as? [String: Any] ?? [:]
            let code = error["code"] as? String ?? "unknown"
            // Codes identify failure without echoing provider messages that may contain credentials.
            throw LullyError(message: "OpenAI Realtime error (\(code)). Check model access, billing, and API key settings.")
        }
        if type == "response.done" {
            let response = json["response"] as? [String: Any] ?? [:]
            guard response["status"] as? String == "completed" else {
                let details = response["status_details"] as? [String: Any] ?? [:]
                let error = details["error"] as? [String: Any] ?? [:]
                let reason = error["code"] as? String ?? details["reason"] as? String ?? response["status"] as? String ?? "incomplete"
                throw LullyError(message: "OpenAI Realtime could not finish (\(reason)). Check billing and model access or try again.")
            }
            return StreamDelta(text: "", finished: true)
        }
        return StreamDelta(text: type == "response.output_text.delta" ? json["delta"] as? String ?? "" : "", finished: false)
    }

    static func answer(model: String, key: String, deep: Bool, prompt: String, screen: String, jpeg: Data?, transcript: String, history: [ChatMessage], update: @escaping @MainActor (String) -> Void) async throws {
        guard !key.isEmpty else { throw LullyError(message: "Add your OpenAI API key in Settings.") }
        guard !model.isEmpty, model.allSatisfy({ $0.isLetter || $0.isNumber || "-._".contains($0) }) else { throw LullyError(message: "Enter a valid model ID in Settings.") }
        var request = URLRequest(url: URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        let session = URLSession(configuration: .ephemeral)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 8 * 1024 * 1024
        socket.resume()
        let deadline = Task {
            try await Task.sleep(nanoseconds: 120_000_000_000)
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { deadline.cancel(); socket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
        try await withTaskCancellationHandler {
            var accumulated = ""
            var sent = false
            do {
                while true {
                    try Task.checkCancellation()
                    let message = try await socket.receive()
                    let data: Data
                    switch message { case .string(let value): data = Data(value.utf8); case .data(let value): data = value; @unknown default: continue }
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LullyError(message: "OpenAI returned an invalid Realtime event.") }
                    let delta = try parse(json)
                    if json["type"] as? String == "session.created", !sent {
                        sent = true
                        for event in events(prompt: prompt, screen: screen, jpeg: jpeg, transcript: transcript, history: history, deep: deep) {
                            let payload = try JSONSerialization.data(withJSONObject: event)
                            try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
                        }
                    }
                    accumulated += delta.text
                    if !delta.text.isEmpty { await update(accumulated) }
                    if delta.finished {
                        guard !accumulated.isEmpty else { throw LullyError(message: "OpenAI returned no answer text.") }
                        return
                    }
                }
            } catch {
                try Task.checkCancellation()
                if let status = (socket.response as? HTTPURLResponse)?.statusCode, status != 101 {
                    throw LullyError(message: "OpenAI Realtime HTTP \(status). Check the API key, model access, and billing.")
                }
                throw error
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }
}
