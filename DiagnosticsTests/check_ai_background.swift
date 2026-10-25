import Foundation

// UIKit stand-in: exercise the production lifetime code without network or an iPhone.
struct UIBackgroundTaskIdentifier: Equatable { let raw: Int; static let invalid = Self(raw: -1) }
@MainActor final class UIApplication {
    static let shared = UIApplication()
    var begins = 0
    var ends = 0
    var expire: (() -> Void)?
    func beginBackgroundTask(withName: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        begins += 1; expire = expirationHandler
        return .init(raw: begins)
    }
    func endBackgroundTask(_ token: UIBackgroundTaskIdentifier) { precondition(token != .invalid); ends += 1 }
}
enum AIClient { enum AIError: Error { case requestFailed(String) } }

@main struct BackgroundChecks {
    @MainActor static func main() async throws {
        let app = UIApplication.shared
        let value = try await AIBackgroundExecution.run { "complete" }
        precondition(value == "complete" && app.begins == 1 && app.ends == 1)
        enum Failure: Error { case expected }
        do { _ = try await AIBackgroundExecution.run { throw Failure.expected }; preconditionFailure() }
        catch Failure.expected { }
        precondition(app.begins == 2 && app.ends == 2)
        let expiring = Task {
            try await AIBackgroundExecution.run { try await Task.sleep(for: .seconds(10)); return "unexpected" }
        }
        while app.begins < 3 { await Task.yield() }
        app.expire?()
        do { _ = try await expiring.value; preconditionFailure("Expiration must cancel work") }
        catch AIClient.AIError.requestFailed { }
        precondition(app.ends == 3)
        let cancelled = Task {
            try await AIBackgroundExecution.run { try await Task.sleep(for: .seconds(10)); return "unexpected" }
        }
        while app.begins < 4 { await Task.yield() }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Parent cancellation must propagate") }
        catch is CancellationError { }
        precondition(app.begins == 4 && app.ends == 4)
        print("PASS: success, failure, expiration and parent cancellation each end background allowance exactly once")
    }
}
