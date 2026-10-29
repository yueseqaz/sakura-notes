import Testing
import Foundation
@testable import SakuraCore
@testable import SakuraStorage
@testable import SakuraSearch

/// Performance measurements on a generated workspace.
/// Numbers are recorded in docs/PERFORMANCE.md with the environment used.
@MainActor
@Suite("Performance", .serialized)
struct PerformanceTests {

    static func generateVault(root: URL, noteCount: Int, paragraphsPerNote: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let words = ["note", "project", "meeting", "idea", "swift", "design", "garden", "travel",
                     "summary", "deadline", "review", "draft", "sakura", "graph", "search", "index"]
        var generator = SystemRandomNumberGenerator()
        for i in 0..<noteCount {
            var body = "# Note \(i)\n\n"
            if i % 7 == 0 { body += "This note mentions [[Note \(max(0, i - 7))]] for linking.\n\n" }
            if i % 11 == 0 { body += "- [ ] task \(i)\n- [x] finished \(i)\n\n" }
            if i % 5 == 0 { body += "Tagged #topic/\(words[i % words.count])\n\n" }
            for p in 0..<paragraphsPerNote {
                body += "Paragraph \(p): " + (0..<40).map { _ in words[Int.random(in: 0..<words.count, using: &generator)] }.joined(separator: " ") + ".\n\n"
            }
            let folder = i % 3 == 0 ? "Projects" : (i % 3 == 1 ? "Journal" : "Archive")
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try body.write(to: dir.appendingPathComponent("Note \(i).md"), atomically: true, encoding: .utf8)
        }
    }

    @Test func largeWorkspaceScanIndexAndSearch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sakura-perf-\(UUID().uuidString)", isDirectory: true)
        let noteCount = 2000
        try Self.generateVault(root: root, noteCount: noteCount, paragraphsPerNote: 8)

        
        var durations: [String: Duration] = [:]

        // 1. Vault scan (full tree).
        let scanStart = SuspendingClock().now
        let vault = try VaultStore(rootURL: root, monitor: false, scanSynchronously: true)
        // The scan publishes its result on the next main-queue turn.
        try await Task.sleep(nanoseconds: 200_000_000)
        durations["scan_2000_notes"] = scanStart.duration(to: .now)
        print("PERF scanned: \(vault.notes.count) of \(noteCount)")
        #expect(vault.notes.count == noteCount)

        // 2. Full index build (analyze + insert every note).
        let dbURL = root.deletingLastPathComponent().appendingPathComponent("perf.sqlite")
        try? FileManager.default.removeItem(at: dbURL)
        let index = FTSIndex(databaseURL: dbURL)
        let indexStart = SuspendingClock().now
        for entry in vault.notes {
            let content = try vault.readNote(entry.relativePath)
            let facts = NoteAnalyzer.analyze(markdown: content, fileName: (entry.relativePath as NSString).deletingPathExtension)
            index.indexNote(FTSIndex.IndexedNote(
                path: entry.relativePath,
                title: facts.title ?? "",
                body: content,
                tags: facts.allTags,
                modificationDate: entry.modificationDate
            ))
        }
        durations["index_2000_notes"] = indexStart.duration(to: .now)
        print("PERF indexed: \(index.noteCount())")

        // 3. Search latency (average of 20 queries).
        let searchStart = SuspendingClock().now
        var resultCount = 0
        for term in ["swift", "meeting", "graph", "sakura", "search"] {
            resultCount += index.search(SearchQuery.parse(term)).count
            resultCount += index.search(SearchQuery.parse("tag:topic/\(term)")).count
            resultCount += index.search(SearchQuery.parse("path:journal \(term)")).count
            resultCount += index.search(SearchQuery.parse("\"\(term)\" -missing")).count
        }
        durations["20_searches"] = searchStart.duration(to: .now)
        #expect(resultCount > 0)

        // 4. Incremental re-index of one note.
        let singleStart = SuspendingClock().now
        let target = vault.notes[0]
        let content = try vault.readNote(target.relativePath)
        let facts = NoteAnalyzer.analyze(markdown: content, fileName: "note")
        index.indexNote(FTSIndex.IndexedNote(path: target.relativePath, title: "note", body: content, tags: facts.allTags, modificationDate: Date()))
        durations["reindex_one_note"] = singleStart.duration(to: .now)

        for (name, duration) in durations.sorted(by: { $0.key < $1.key }) {
            let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
            print("PERF \(name): \(String(format: "%.1f", ms)) ms")
        }

        // Clean up.
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: dbURL)
    }
}
