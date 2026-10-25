import Foundation

@main struct WorkoutDraftChecks {
    @MainActor static func main() throws {
        let url = URL.temporaryDirectory.appendingPathComponent("trace-draft-check-\(UUID())/draft.sqlite")
        let original = Data("{\"sets\":[80,8],\"restEndsAt\":123,\"selected\":2}".utf8)
        do {
            let store = try WorkoutDraftStore(url: url)
            let empty = try store.read()
            precondition(empty == nil)
            try store.write(original)
        }
        do {
            let reopened = try WorkoutDraftStore(url: url)
            let restored = try reopened.read()
            precondition(restored == original, "Completed set, timer and selection must restore together")
            for i in 0..<100 { try reopened.write(Data("snapshot-\(i)".utf8)) }
        }
        let reopened = try WorkoutDraftStore(url: url)
        let last = try reopened.read()
        precondition(last == Data("snapshot-99".utf8), "Newest committed edit must survive reopening")
        // An explicit nil session is a tombstone, preventing legacy resurrection.
        let ended = Data("{\"active\":null,\"restDuration\":0}".utf8)
        try reopened.write(ended)
        let other = try WorkoutDraftStore(url: url)
        let final = try other.read()
        precondition(final == ended)
        let invalid = url.appendingPathComponent("child.sqlite")
        do { _ = try WorkoutDraftStore(url: invalid); preconditionFailure("Invalid storage must throw") }
        catch { /* Expected; the existing database must remain intact. */ }
        let retained = try reopened.read()
        precondition(retained == ended)
        print("PASS: empty store, exact restoration, 100 writes, concurrent reopen, tombstone, storage failure preserves data")
    }
}
