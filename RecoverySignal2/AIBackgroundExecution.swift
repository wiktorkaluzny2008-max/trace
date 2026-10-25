import UIKit

/// A finite execution allowance, not a scheduled job or a guarantee of delivery.
@MainActor
final class AIBackgroundExecution {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private(set) var expired = false

    static func run(_ operation: @escaping @MainActor () async throws -> String) async throws -> String {
        let allowance = AIBackgroundExecution()
        let work = Task { try await operation() }
        allowance.identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish AI response") { [weak allowance] in
            Task { @MainActor in
                guard let allowance else { return }
                allowance.expired = true
                work.cancel()
                allowance.end()
            }
        }
        defer { allowance.end() }
        do {
            return try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
        } catch {
            if allowance.expired {
                throw AIClient.AIError.requestFailed(String(localized: "iOS ended the background request before the reply arrived. Please retry when you return."))
            }
            throw error
        }
    }

    private func end() {
        guard identifier != .invalid else { return }
        let token = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(token)
    }
}
