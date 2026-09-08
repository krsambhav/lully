import Foundation

struct ConversationTurn: Identifiable {
    let id = UUID()
    let question: String
    var answer = ""
    var context = ""
    var pending = true
    var issue = ""
    var firstToken: Double?
}

enum ConversationContext {
    static func messages(from turns: [ConversationTurn]) -> [ChatMessage] {
        turns.filter { !$0.pending && !$0.answer.isEmpty && $0.issue.isEmpty }.flatMap { turn in
            [ChatMessage(role: "user", content: turn.question + turn.context), ChatMessage(role: "assistant", content: turn.answer)]
        }
    }
}
