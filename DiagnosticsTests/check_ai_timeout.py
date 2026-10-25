"""Exercise the production Gemini retry loop with deterministic, non-network responses."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'RecoverySignal2/AIClient.swift').read_text()
loop = source[source.index('    private func sendGemini('):source.index('    // MARK: - On-device')]
loop = loop.replace('private func sendGemini', 'func sendGemini', 1)
stubs = '''
import Foundation
@MainActor final class Responses {
 var values: [String]; var calls = 0; var discoveries = 0
 init(_ values: [String]) { self.values = values }
}
@MainActor struct Client {
 static let fallbackModels = ["fallback-a", "fallback-b"]
 static let modelKey = "diagnostic-unused-model-key"
 enum AIError: Error { case timedOut, overloaded, noModelAvailable }
 enum ModelProblem: Error { case busy, unavailable }
 let responses: Responses
 func nextModel(apiKey: String, excluding: Set<String>) async throws -> String? {
  responses.discoveries += 1; return "primary"
 }
 func generate(model: String, apiKey: String, system: String, user: String, maxTokens: Int, temperature: Double, json: Bool, images: [Data]) async throws -> String {
  responses.calls += 1
  switch responses.values.removeFirst() {
  case "timeout": throw URLError(.timedOut)
  case "cancel": throw CancellationError()
  case "busy": throw ModelProblem.busy
  case "unavailable": throw ModelProblem.unavailable
  default: return "OK"
  }
 }
'''
tests = '''
}
@main struct Checks {
 @MainActor static func main() async throws {
  for scenario in [["timeout", "ok"], ["timeout", "timeout"], ["cancel"], ["timeout", "busy"], ["timeout", "unavailable"]] {
   let responses = Responses(scenario)
   do {
    let value = try await Client(responses: responses).sendGemini(apiKey: "test", system: "", user: "", maxTokens: 1, temperature: 0, json: true, images: [])
    precondition(scenario.last == "ok" && value == "OK")
   } catch {
    precondition(scenario.last != "ok")
    if scenario == ["cancel"] { precondition(error is CancellationError) }
   }
   precondition(responses.calls == scenario.count)
   precondition(responses.discoveries == 1)
  }
  print("PASS: timeout recovery, bounded failure, cancellation and no repeated discovery")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='trace-timeout-') as tmp:
    path = Path(tmp)/'Checks.swift'; path.write_text(stubs+loop+tests)
    binary = str(Path(tmp)/'checks')
    subprocess.run(['swiftc','-parse-as-library','-module-cache-path','/tmp/trace-swift-module-cache',str(path),'-o',binary],check=True)
    subprocess.run([binary],check=True)
