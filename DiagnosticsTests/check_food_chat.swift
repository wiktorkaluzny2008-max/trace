import Foundation

@main
struct FoodChatChecks {
    static func main() throws {
        let valid = #"{"reply":"Sprawdź porcję","foods":[{"name":"Jajka","grams":100,"calories":155,"protein":13,"carbs":1,"fat":11,"date":"2026-10-08","meal":"breakfast"}]}"#
        func decode(_ text: String) throws -> FoodChatReply {
            try JSONDecoder().decode(FoodChatReply.self, from: Data(text.utf8))
        }
        let reply = try decode(valid)
        let proposal = try reply.proposals()[0]
        precondition(proposal.food.source == .estimate)
        precondition(proposal.slotRaw == "breakfast")
        precondition(abs(proposal.food.amount(200).kcal - 310) < 0.001)
        precondition(FoodChatReply.date("2026-02-30") == nil)
        precondition(FoodChatReply.date("08/10/2026") == nil)
        for broken in [valid.replacingOccurrences(of: "2026-10-08", with: "2026-02-30"),
                       valid.replacingOccurrences(of: "breakfast", with: "unknown"),
                       valid.replacingOccurrences(of: "\"grams\":100", with: "\"grams\":0"),
                       valid.replacingOccurrences(of: "\"calories\":155", with: "\"calories\":9999"),
                       valid.replacingOccurrences(of: "\"protein\":13", with: "\"protein\":-1")] {
            do { _ = try decode(broken).proposals(); preconditionFailure("Invalid proposal accepted") }
            catch { }
        }
        let message = FoodChatMessage(role: "assistant", text: reply.reply, foods: [proposal])
        let restored = try JSONDecoder().decode(FoodChatMessage.self, from: JSONEncoder().encode(message))
        precondition(restored.id == message.id && restored.foods[0].food.id == proposal.food.id)
        precondition(restored.foods[0].date == proposal.date)
        precondition(restored.text == "Sprawdź porcję")
        print("PASS: portion scaling, invalid dates/macros/slots, Polish text and stable IDs through persistence")
    }
}
