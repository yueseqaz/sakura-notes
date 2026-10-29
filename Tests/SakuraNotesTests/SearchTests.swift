import Testing
import Foundation
@testable import SakuraCore
@testable import SakuraSearch

@Suite("FTS Index")
struct FTSIndexTests {

    func makeIndex() -> FTSIndex {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fts-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FTSIndex(databaseURL: dir.appendingPathComponent("index.sqlite"))
    }

    func note(_ path: String, _ title: String, _ body: String, tags: [String] = [], mtime: Date = Date()) -> FTSIndex.IndexedNote {
        FTSIndex.IndexedNote(path: path, title: title, body: body, tags: tags, modificationDate: mtime)
    }

    @Test func indexesAndSearchesTerms() {
        let index = makeIndex()
        index.indexNote(note("a.md", "Swift Concurrency", "async await actors and structured concurrency"))
        index.indexNote(note("b.md", "Gardening", "how to grow tomatoes and basil"))

        let results = index.search(SearchQuery.parse("concurrency"))
        #expect(results.map(\.path) == ["a.md"])
        #expect(results[0].snippet.contains("<mark>"))

        let tomatoes = index.search(SearchQuery.parse("tomatoes"))
        #expect(tomatoes.map(\.path) == ["b.md"])
    }

    @Test func prefixAndPhraseMatching() {
        let index = makeIndex()
        index.indexNote(note("a.md", "Meeting Notes", "discussed the quarterly roadmap and hiring plans"))
        #expect(!index.search(SearchQuery.parse("quarter")).isEmpty) // prefix
        #expect(!index.search(SearchQuery.parse("\"quarterly roadmap\"")).isEmpty) // phrase
        #expect(index.search(SearchQuery.parse("\"roadmap quarterly\"")).isEmpty) // wrong order
    }

    @Test func exclusionFiltersResults() {
        let index = makeIndex()
        index.indexNote(note("a.md", "Swift", "swift language notes"))
        index.indexNote(note("b.md", "Swift UI", "swiftui views and state"))
        let both = index.search(SearchQuery.parse("swift"))
        #expect(both.count == 2)
        let onlyLanguage = index.search(SearchQuery.parse("swift -swiftui"))
        #expect(onlyLanguage.map(\.path) == ["a.md"])
    }

    @Test func operatorFilters() {
        let index = makeIndex()
        index.indexNote(note("journal/2026/plan.md", "Plan", "focus and goals", tags: ["work", "planning"]))
        index.indexNote(note("recipes/soup.md", "Soup", "tasty ingredients", tags: ["cooking"]))

        #expect(index.search(SearchQuery.parse("tag:work")).map(\.path) == ["journal/2026/plan.md"])
        #expect(index.search(SearchQuery.parse("path:recipes")).map(\.path) == ["recipes/soup.md"])
        #expect(index.search(SearchQuery.parse("ext:md")).count == 2)
        #expect(index.search(SearchQuery.parse("title:soup")).map(\.path) == ["recipes/soup.md"])
        #expect(index.search(SearchQuery.parse("tag:cooking tag:work")).isEmpty) // AND semantics
    }

    @Test func dateFilters() {
        let index = makeIndex()
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        let new = Date()
        index.indexNote(note("old.md", "Old", "content", mtime: old))
        index.indexNote(note("new.md", "New", "content", mtime: new))
        #expect(index.search(SearchQuery.parse("content after:2000-01-01")).count == 2)
        let recentOnly = index.search(SearchQuery.parse("content before:\(Self.iso(old))"))
        #expect(recentOnly.map(\.path) == ["old.md"])
    }

    static func iso(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date) // "before:" includes the whole given day
    }

    @Test func cjkQueriesFallBackToSubstringMatch() {
        let index = makeIndex()
        index.indexNote(note("cjk.md", "日本語ノート", "これは日本語のテキストです。tokyo"))
        #expect(!index.search(SearchQuery.parse("日本語")).isEmpty)
        #expect(!index.search(SearchQuery.parse("テキスト")).isEmpty)
        #expect(index.search(SearchQuery.parse("tokyo")).count == 1)
    }

    @Test func updatesAndRemoval() {
        let index = makeIndex()
        index.indexNote(note("a.md", "Original", "first content"))
        index.indexNote(note("a.md", "Updated", "second content"))
        #expect(index.noteCount() == 1)
        let results = index.search(SearchQuery.parse("second"))
        #expect(results.count == 1)
        #expect(index.search(SearchQuery.parse("first")).isEmpty)

        index.removeNote("a.md")
        #expect(index.noteCount() == 0)
        #expect(index.search(SearchQuery.parse("second")).isEmpty)
    }

    @Test func unlinkedMentionLookup() {
        let index = makeIndex()
        index.indexNote(note("a.md", "Project Phoenix", "the kickoff notes"))
        index.indexNote(note("b.md", "Daily", "we discussed Project Phoenix today"))
        index.indexNote(note("c.md", "Other", "unrelated"))
        let mentions = index.notesContaining(text: "Project Phoenix", excludingPath: "a.md")
        #expect(mentions == ["b.md"])
    }

    @Test func rebuiltFromScratch() {
        let index = makeIndex()
        index.indexNote(note("a.md", "One", "alpha"))
        index.indexNote(note("b.md", "Two", "beta"))
        index.removeAll()
        #expect(index.noteCount() == 0)
        index.indexNote(note("a.md", "One", "alpha"))
        #expect(index.search(SearchQuery.parse("alpha")).count == 1)
    }
}

@MainActor
@Suite("Link Index")
struct LinkIndexTests {

    func facts(_ markdown: String, fileName: String) -> NoteFacts {
        NoteAnalyzer.analyze(markdown: markdown, fileName: fileName)
    }

    @Test func resolvesByPathTitleAndFilename() {
        let index = LinkIndex()
        index.update(path: "notes/project-phoenix.md", facts: facts("# Project Phoenix\nsee [[Daily]]", fileName: "project-phoenix"))
        index.update(path: "daily/2026-01-01.md", facts: facts("# Daily\nref to [[Project Phoenix]]", fileName: "2026-01-01"))

        #expect(index.resolve(target: "daily/2026-01-01.md", fromFolder: "") == "daily/2026-01-01.md")
        #expect(index.resolve(target: "Project Phoenix", fromFolder: "daily") == "notes/project-phoenix.md")
        #expect(index.resolve(target: "2026-01-01", fromFolder: "") == "daily/2026-01-01.md")
        #expect(index.resolve(target: "missing", fromFolder: "") == nil)
    }

    @Test func backlinksAndOrphans() {
        let index = LinkIndex()
        index.update(path: "a.md", facts: facts("# A\nlinks to [[B]]", fileName: "a"))
        index.update(path: "b.md", facts: facts("# B\nno links here", fileName: "b"))
        index.update(path: "c.md", facts: facts("# C\nalso links [[B]]", fileName: "c"))
        index.update(path: "d.md", facts: facts("# D\nisland note", fileName: "d"))

        #expect(index.backlinks(to: "b.md").sorted() == ["a.md", "c.md"])
        // "Orphans" = notes nothing links to (a and c only have outgoing links).
        #expect(index.orphanNotes().sorted() == ["a.md", "c.md", "d.md"])
        #expect(index.brokenLinks(from: "a.md").isEmpty)
    }

    @Test func brokenLinksDetected() {
        let index = LinkIndex()
        index.update(path: "a.md", facts: facts("# A\npoints at [[Ghost Note]]", fileName: "a"))
        #expect(index.brokenLinks(from: "a.md") == ["Ghost Note"])
        #expect(index.allBrokenLinkSources() == ["a.md"])
        // Once the target exists, the link resolves.
        index.update(path: "ghost note.md", facts: facts("# Ghost Note", fileName: "ghost note"))
        #expect(index.resolve(target: "Ghost Note", fromFolder: "") == "ghost note.md")
        #expect(index.brokenLinks(from: "a.md").isEmpty)
    }

    @Test func renameRemapsBacklinks() {
        let index = LinkIndex()
        index.update(path: "old.md", facts: facts("# Old Title", fileName: "old"))
        index.update(path: "x.md", facts: facts("# X\n[[Old Title]]", fileName: "x"))
        index.rename(from: "old.md", to: "new.md")
        #expect(index.backlinks(to: "new.md") == ["x.md"])
        #expect(index.backlinks(to: "old.md").isEmpty)
    }

    @Test func unlinkedMentionsExcludesLinkedNotes() {
        let index = LinkIndex()
        index.update(path: "target.md", facts: facts("# Target Note", fileName: "target"))
        index.update(path: "linker.md", facts: facts("# L\nsee [[Target Note]]", fileName: "linker"))
        index.update(path: "mentioner.md", facts: facts("# M\nTarget Note is great", fileName: "mentioner"))
        // FTS-based mention lookup is covered in FTSIndexTests; here the
        // backlink exclusion is what matters.
        #expect(index.backlinks(to: "target.md") == ["linker.md"])
    }
}
