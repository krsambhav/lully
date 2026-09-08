import Foundation

final class CloudTests {
    func testGeminiUsesFixedHostHeaderKeyAndVision() throws {
        let request = try CloudAssistant.request(provider: .gemini, model: "gemini-3.8-flash", key: "test-secret", deep: false, prompt: "Explain", screen: "Example", jpeg: Data([1, 2]), transcript: "Hello")
        expectEqual(request.url?.host, "generativelanguage.googleapis.com")
        expectFalse(request.url!.absoluteString.contains("test-secret"))
        expectEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-secret")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let contents = body["contents"] as! [[String: Any]]
        let parts = contents[0]["parts"] as! [[String: Any]]
        expectNotNil(parts.last?["inlineData"])
        let config = body["generationConfig"] as! [String: Any]
        expectEqual((config["thinkingConfig"] as! [String: String])["thinkingLevel"], "low")
    }

    func testRejectsMissingKeyAndModelPathInjection() {
        for (key, model) in [("", "gemini-3.8-flash"), ("test", "../../other?key=bad")] {
            expectThrows(try CloudAssistant.request(provider: .gemini, model: model, key: key, deep: false, prompt: "", screen: "", jpeg: nil, transcript: ""))
        }
    }

    func testOpenAIUsesResponsesAndDisablesStorage() throws {
        let request = try CloudAssistant.request(provider: .openai, model: "gpt-5.6-sol", key: "test", deep: true, prompt: "Explain", screen: "", jpeg: nil, transcript: "")
        expectEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        expectEqual(body["store"] as? Bool, false)
        expectEqual((body["reasoning"] as! [String: String])["effort"], "high")
    }

    func testGeminiOnlyDisplaysAnswerAndRecognizesCompletion() throws {
        let event = Data(#"{"candidates":[{"content":{"parts":[{"thought":true,"text":"internal"},{"text":"4"}]},"finishReason":"STOP"}]}"#.utf8)
        let delta = try CloudAssistant.parse(event, provider: .gemini)
        expectEqual(delta.text, "4")
        expectTrue(delta.finished)
    }

    func testFailuresAreNotTreatedAsFinishedAnswers() {
        let events: [(Provider, String)] = [(.gemini, #"{"candidates":[{"finishReason":"MAX_TOKENS"}]}"#), (.gemini, #"{"promptFeedback":{"blockReason":"SAFETY"}}"#), (.openai, #"{"type":"response.incomplete"}"#), (.openai, #"{"error":{"message":"quota"}}"#)]
        for (provider, event) in events { expectThrows(try CloudAssistant.parse(Data(event.utf8), provider: provider)) }
    }

    func testOpenAITextAndCompletionAreSeparateEvents() throws {
        let text = try CloudAssistant.parse(Data(#"{"type":"response.output_text.delta","delta":"4"}"#.utf8), provider: .openai)
        expectEqual(text.text, "4")
        expectFalse(text.finished)
        let completion = try CloudAssistant.parse(Data(#"{"type":"response.completed"}"#.utf8), provider: .openai)
        expectTrue(completion.finished)
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Values differ") }
func expectTrue(_ a: Bool) { precondition(a, "Expected true") }
func expectFalse(_ a: Bool) { precondition(!a, "Expected false") }
func expectNotNil<T>(_ a: T?) { precondition(a != nil, "Expected value") }
func expectThrows<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression() } catch { return }
    fatalError("Expected an error")
}

let checks = CloudTests()
try checks.testGeminiUsesFixedHostHeaderKeyAndVision()
checks.testRejectsMissingKeyAndModelPathInjection()
try checks.testOpenAIUsesResponsesAndDisablesStorage()
try checks.testGeminiOnlyDisplaysAnswerAndRecognizesCompletion()
checks.testFailuresAreNotTreatedAsFinishedAnswers()
try checks.testOpenAITextAndCompletionAreSeparateEvents()
print("6 checks passed: routing, credentials, vision input, reasoning, streaming, and error handling.")

expectTrue(ShortcutSpec.hideDefault.valid)
expectTrue(ShortcutSpec.pinDefault.valid)
expectTrue(ShortcutSpec.captureDefault.valid)
expectFalse(ShortcutSpec.hideDefault == ShortcutSpec.pinDefault)
expectFalse(ShortcutSpec.hideDefault == ShortcutSpec.captureDefault)
expectFalse(ShortcutSpec.pinDefault == ShortcutSpec.captureDefault)
expectFalse(ShortcutSpec(key: "KeyA", command: false, option: false, control: false, shift: true).valid)
expectFalse(ShortcutSpec(key: "Escape", command: true, option: false, control: false, shift: false).valid)
let encodedShortcut = try JSONEncoder().encode(ShortcutSpec.captureDefault)
expectEqual(try JSONDecoder().decode(ShortcutSpec.self, from: encodedShortcut), ShortcutSpec.captureDefault)
expectEqual(ShortcutSpec.captureDefault.label, "⌃ ⌥ S")
print("Shortcut checks passed: valid defaults, distinct combinations, unsupported keys, persistence encoding, labels.")

var firstTurn = ConversationTurn(question: "Remember the number 42.")
firstTurn.answer = "I will remember 42."
firstTurn.pending = false
let unfinished = ConversationTurn(question: "Pending request")
let chatContext = ConversationContext.messages(from: [firstTurn, unfinished])
expectEqual(chatContext.count, 2)
expectEqual(chatContext[0].role, "user")
expectEqual(chatContext[1].role, "assistant")
expectEqual(chatContext[0].content, "Remember the number 42.")
expectEqual(ConversationContext.messages(from: []).count, 0)
let followup = try CloudAssistant.request(provider: .gemini, model: "gemini-3.8-flash", key: "test", deep: false, prompt: "Which number?", screen: "", jpeg: nil, transcript: "", history: chatContext)
let followupBody = try JSONSerialization.jsonObject(with: followup.httpBody!) as! [String: Any]
let contents = followupBody["contents"] as! [[String: Any]]
expectEqual(contents.count, 3)
expectEqual(contents[1]["role"] as? String, "model")
let newQuestionParts = contents[2]["parts"] as! [[String: Any]]
expectEqual(newQuestionParts.count, 1)
expectTrue(newQuestionParts[0]["inlineData"] == nil)
let fresh = try CloudAssistant.request(provider: .gemini, model: "gemini-3.8-flash", key: "test", deep: false, prompt: "Hello", screen: "", jpeg: nil, transcript: "", history: ConversationContext.messages(from: []))
let freshBody = try JSONSerialization.jsonObject(with: fresh.httpBody!) as! [String: Any]
expectEqual((freshBody["contents"] as! [[String: Any]]).count, 1)
print("Conversation checks passed: follow-up history, pending-turn exclusion, explicit image input, fresh context.")
let display = CGRect(x: 0, y: 25, width: 1440, height: 875)
let window = CGRect(x: 100, y: 100, width: 480, height: 680)
expectEqual(WindowMovement.origin(frame: window, visible: display, dx: -1000, dy: -1000), CGPoint(x: 0, y: 25))
expectEqual(WindowMovement.origin(frame: window, visible: display, dx: 10000, dy: 10000), CGPoint(x: 960, y: 220))
expectEqual(WindowMovement.origin(frame: window, visible: display, dx: 14, dy: 0), CGPoint(x: 114, y: 100))
print("Movement checks passed: directional stepping and display bounds.")
var recoveryAttempts = 0
try await CloudAssistant.withRecovery(delay: 0) {
    recoveryAttempts += 1
    if recoveryAttempts == 1 { throw InterruptedResponse.incomplete }
}
expectEqual(recoveryAttempts, 2)
var failedAttempts = 0
do {
    try await CloudAssistant.withRecovery(delay: 0) {
        failedAttempts += 1
        throw URLError(.networkConnectionLost)
    }
    fatalError("Expected interrupted transport to fail after one retry")
} catch { expectEqual(failedAttempts, 2) }
var rejectedAttempts = 0
do {
    try await CloudAssistant.withRecovery(delay: 0) {
        rejectedAttempts += 1
        throw LullyError(message: "Provider rejection")
    }
} catch { expectEqual(rejectedAttempts, 1) }
var interruptedTurn = ConversationTurn(question: "Question")
interruptedTurn.answer = "Partial"
interruptedTurn.pending = false
interruptedTurn.issue = "Interrupted"
expectTrue(ConversationContext.messages(from: [interruptedTurn]).isEmpty)
print("Recovery checks passed: retry success, bounded transport failures, no retry on provider errors, incomplete history exclusion.")
let realtime = RealtimeAssistant.events(prompt: "Explain", screen: "", jpeg: Data([1, 2]), transcript: "Spoken question", history: [ChatMessage(role: "user", content: "First question"), ChatMessage(role: "assistant", content: "First answer")], deep: false)
expectEqual(realtime.count, 5)
expectEqual(realtime[0]["type"] as? String, "session.update")
let previousAnswer = realtime[2]["item"] as! [String: Any]
expectEqual(previousAnswer["role"] as? String, "assistant")
expectEqual((previousAnswer["content"] as! [[String: Any]])[0]["type"] as? String, "output_text")
let currentInput = (realtime[3]["item"] as! [String: Any])["content"] as! [[String: Any]]
expectEqual(currentInput.count, 2)
expectTrue((currentInput[0]["text"] as! String).contains("Spoken question"))
expectEqual(currentInput[1]["image_url"] as? String, "data:image/jpeg;base64,AQI=")
expectEqual(try RealtimeAssistant.parse(["type": "response.output_text.delta", "delta": "Hello"]).text, "Hello")
expectTrue(try RealtimeAssistant.parse(["type": "response.done", "response": ["status": "completed"]]).finished)
expectThrows(try RealtimeAssistant.parse(["type": "response.done", "response": ["status": "failed"]]))
expectThrows(try RealtimeAssistant.parse(["type": "error", "error": ["code": "invalid_api_key"]]))
print("Realtime checks passed: session setup, history, explicit image and transcript input, completion and failure events.")
let resized = WindowResize.frame(window, factor: 1.07, minimum: CGSize(width: 420, height: 560), visible: display)
expectTrue(abs(resized.midX - window.midX) < 0.001)
expectTrue(abs(resized.midY - window.midY) < 0.001)
expectTrue(resized.width > window.width)
let smallest = WindowResize.frame(window, factor: 0.01, minimum: CGSize(width: 420, height: 560), visible: display)
expectEqual(smallest.size, CGSize(width: 420, height: 560))
let largest = WindowResize.frame(window, factor: 100, minimum: CGSize(width: 420, height: 560), visible: display)
expectEqual(largest, display)
print("Resize checks passed: centered growth, minimum size, display bounds.")
