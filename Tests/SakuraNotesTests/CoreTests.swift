import Testing
import Foundation
@testable import SakuraCore

@Suite("Front Matter")
struct FrontMatterTests {

    @Test func extractsSimpleScalars() {
        let source = """
        ---
        title: My Note
        date: 2026-10-30
        ---

        # Body
        """
        let (matter, bodyRange) = FrontMatter.extract(from: source)
        #expect(matter.title == "My Note")
        #expect(matter["date"] == .scalar("2026-10-30"))
        #expect(bodyRange != nil)
        #expect(String(source[bodyRange!]).hasPrefix("\n# Body"))
    }

    @Test func extractsFlowStyleLists() {
        let (matter, _) = FrontMatter.extract(from: "---\ntags: [alpha, beta]\n---\nbody")
        #expect(matter.tags == ["alpha", "beta"])
    }

    @Test func extractsBlockStyleLists() {
        let (matter, _) = FrontMatter.extract(from: "---\ntags:\n  - one\n  - two\n---\nbody")
        #expect(matter.tags == ["one", "two"])
    }

    @Test func absentFrontMatterYieldsEmpty() {
        let (matter, bodyRange) = FrontMatter.extract(from: "# Just a note\n")
        #expect(matter.entries.isEmpty)
        #expect(bodyRange == nil)
    }

    @Test func unterminatedFrontMatterIsBody() {
        let (matter, _) = FrontMatter.extract(from: "---\ntitle: never closed\nmore text")
        #expect(matter.entries.isEmpty)
    }

    @Test func unknownKeysSurviveRoundTrip() {
        let source = "---\ntitle: T\ncustom_key: keep me\n---\n\nbody"
        let (matter, _) = FrontMatter.extract(from: source)
        #expect(matter["custom_key"] == .scalar("keep me"))
        let serialized = matter.serialized()
        let (reparsed, _) = FrontMatter.extract(from: serialized + "body")
        #expect(reparsed["custom_key"] == .scalar("keep me"))
        #expect(reparsed.title == "T")
    }
}

@Suite("Note Analyzer")
struct NoteAnalyzerTests {

    @Test func extractsOutlineTagsTasksAndLinks() {
        let source = """
        # Top

        ## Section One

        Some text with #alpha and #beta/sub tags.

        - [ ] open task
        - [x] done task
        - [ ] due task @due(2026-12-01)

        Link to [[Other Note]] and [[Target|display]] plus [external](https://example.com).
        """
        let facts = NoteAnalyzer.analyze(markdown: source, fileName: "test")
        #expect(facts.outline.count == 2)
        #expect(facts.outline[0].title == "Top")
        #expect(facts.outline[1].level == 2)
        #expect(facts.inlineTags.contains("alpha"))
        #expect(facts.inlineTags.contains("beta/sub"))
        #expect(facts.tasks.count == 3)
        #expect(facts.tasks[0].isCompleted == false)
        #expect(facts.tasks[1].isCompleted == true)
        #expect(facts.tasks[0].text == "open task")
        #expect(facts.tasks[2].dueDate != nil)
        let wikiLinks = facts.links.filter {
            if case .wikiLink = $0.kind { return true }
            return false
        }
        #expect(wikiLinks.count == 2)
        let external = facts.links.filter {
            if case .external = $0.kind { return true }
            return false
        }
        #expect(external.count == 1)
    }

    @Test func ignoresTagsAndLinksInCode() {
        let source = """
        ```
        #notATag [[Not A Link]]
        ```
        Inline `#alsoNotTag` stays out.
        """
        let facts = NoteAnalyzer.analyze(markdown: source, fileName: "t")
        #expect(facts.inlineTags.isEmpty)
        #expect(facts.links.isEmpty)
    }

    @Test func wordCountHandlesCJKAndLatin() {
        #expect(StringUtilities.wordCount("hello world") == 2)
        #expect(StringUtilities.wordCount("你好世界") == 4)
        #expect(StringUtilities.wordCount("hello 你好") == 3)
        #expect(StringUtilities.wordCount("") == 0)
    }

    @Test func titleFallsBackThroughFrontMatterHeadingFileName() {
        let fromFrontMatter = NoteAnalyzer.analyze(markdown: "---\ntitle: FM\n---\n# Heading", fileName: "file")
        #expect(fromFrontMatter.title == "FM")
        let fromHeading = NoteAnalyzer.analyze(markdown: "# Heading", fileName: "file")
        #expect(fromHeading.title == "Heading")
        let fromFile = NoteAnalyzer.analyze(markdown: "plain text", fileName: "file")
        #expect(fromFile.title == "file")
    }

    @Test func headingTitlesArePlainText() {
        let facts = NoteAnalyzer.analyze(markdown: "## A **bold** heading", fileName: "t")
        #expect(facts.outline.first?.title == "A bold heading")
    }
}

@Suite("HTML Renderer")
struct HTMLRendererTests {

    @Test func dropsRawHTMLForSafety() {
        // Block-level raw HTML is dropped entirely; inline tags are dropped
        // while their text content is kept (escaped), like CommonMark renderers.
        let html = HTMLRenderer.render("before <script>alert(1)</script> after")
        #expect(!html.contains("<script"))
        #expect(html.contains("before"))
        #expect(html.contains("after"))
        let blockHTML = HTMLRenderer.render("<div onclick=\"x\">block</div>\n\ntext")
        #expect(!blockHTML.contains("<div"))
        #expect(!blockHTML.contains("onclick"))
    }

    @Test func escapesHtmlInText() {
        let html = HTMLRenderer.render("a < b & c > d")
        #expect(html.contains("a &lt; b &amp; c &gt; d"))
    }

    @Test func rendersTablesWithAlignment() {
        let html = HTMLRenderer.render("| L | C |\n|---|:-:|\n| a | b |")
        #expect(html.contains("<table>"))
        #expect(html.contains("text-align:center"))
        #expect(html.contains("<td>a</td>"))
    }

    @Test func rendersTaskListCheckboxes() {
        let html = HTMLRenderer.render("- [ ] todo\n- [x] done")
        #expect(html.contains("task-item"))
        #expect(html.contains("checked"))
        #expect(!html.contains("[ ]"))
    }

    @Test func mermaidBlocksBecomeDivs() {
        let html = HTMLRenderer.render("```mermaid\ngraph TD; A-->B;\n```")
        #expect(html.contains(#"<div class="mermaid">"#))
        #expect(html.contains("A--&gt;B;"))
    }

    @Test func codeBlocksCarryLanguageClass() {
        let html = HTMLRenderer.render("```swift\nlet x = 1\n```")
        #expect(html.contains("language-swift"))
    }

    @Test func stripsFrontMatterFromRendering() {
        let md = "---\ntitle: T\n---\n\n# Real content"
        let html = HTMLRenderer.render(FrontMatter.extract(from: md).bodyRange.map { String(md[$0]) } ?? md)
        #expect(html.contains("Real content"))
        #expect(!html.contains("title:"))
    }

    @Test func tocAnchorsAreStable() {
        let toc = HTMLRenderer.tableOfContents("# One\n## Two Words\n### Three!")
        #expect(toc.count == 3)
        #expect(toc[1].anchor == "two-words")
    }
}

@Suite("Line Diff")
struct LineDiffTests {

    @Test func detectsInsertionsAndDeletions() {
        let source = "one\ntwo\nthree"
        let dest = "one\nTWO\nthree\nfour"
        let result = LineDiff.diff(source, dest)
        #expect(result.addedCount == 2) // "TWO" replaces "two", plus "four"
        #expect(result.removedCount == 1)
        #expect(result.operations.contains { insert in
            if case .insert(let lines, _) = insert { return lines == ["four"] }
            return false
        })
    }

    @Test func identicalTextsProduceNoChanges() {
        let result = LineDiff.diff("a\nb", "a\nb")
        #expect(result.addedCount == 0 && result.removedCount == 0)
    }

    @Test func applyRoundTrips() {
        let source = "one\ntwo\nthree\nfour"
        let dest = "one\nTWO\nthree\nfour\nfive"
        let result = LineDiff.diff(source, dest)
        let applied = LineDiff.apply(operations: result.operations, to: source)
        #expect(applied == dest + "\n")
    }

    @Test func largeInputsDegradeGracefully() {
        let big = Array(repeating: "line", count: 9000).joined(separator: "\n")
        let result = LineDiff.diff(big, big + "\nextra")
        #expect(result.removedCount + result.addedCount > 0)
    }
}

@Suite("Search Query Parser")
struct SearchQueryParserTests {

    @Test func parsesTermsAndPhrases() {
        let q = SearchQuery.parse("apple \"fruit salad\" banana")
        #expect(q.terms == ["apple", "banana"])
        #expect(q.phrases == ["fruit salad"])
    }

    @Test func parsesOperators() {
        let q = SearchQuery.parse("meeting tag:work path:2026/journal ext:md title:plan -draft after:2026-01-01 before:2026-12-31")
        #expect(q.requiredTags == ["work"])
        #expect(q.pathFilters == ["2026/journal"])
        #expect(q.extensions == ["md"])
        #expect(q.titleFilters == ["plan"])
        #expect(q.excludedTerms == ["draft"])
        #expect(q.modifiedAfter != nil)
        #expect(q.modifiedBefore != nil)
    }

    @Test func extDotPrefixIsStripped() {
        let q = SearchQuery.parse("ext:.pdf")
        #expect(q.extensions == ["pdf"])
    }

    @Test func emptyQueryIsEmpty() {
        #expect(SearchQuery.parse("   ").isEmpty)
    }
}

@Suite("Template Engine")
struct TemplateEngineTests {

    @Test func expandsDateVariables() {
        let date = Date(timeIntervalSince1970: 1_797_600_000) // 2026-12-01-ish UTC
        let engine = TemplateEngine(title: "Meeting", date: date, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!)
        let out = engine.expand("# {{title}} on {{date}} at {{time}} ({{year}}-{{month}}-{{day}})")
        #expect(out.hasPrefix("# Meeting on 2026-"))
        #expect(out.contains("2026"))
        #expect(!out.contains("{{"))
    }

    @Test func customFormatPattern() {
        let engine = TemplateEngine(title: "T", date: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!)
        #expect(engine.expand("{{date:yyyy/MM/dd}}") == "1970/01/01")
    }

    @Test func unknownVariablesPassThrough() {
        let engine = TemplateEngine(title: "T")
        #expect(engine.expand("{{nope}}") == "{{nope}}")
    }
}

@Suite("String Utilities")
struct StringUtilitiesTests {

    @Test func sanitizesFileNames() {
        #expect(StringUtilities.sanitizedFileName("a/b:c") == "a-b-c")
        #expect(StringUtilities.sanitizedFileName("  .hidden.  ") == "hidden")
        #expect(StringUtilities.sanitizedFileName("   ") == "Untitled")
    }

    @Test func relativePathWithinTree() {
        let dir = URL(fileURLWithPath: "/vault/folder/sub")
        let file = URL(fileURLWithPath: "/vault/other/note.md")
        #expect(StringUtilities.relativePath(from: dir, to: file) == "../../other/note.md")
        let sibling = URL(fileURLWithPath: "/vault/folder/sub/note.md")
        #expect(StringUtilities.relativePath(from: dir, to: sibling) == "note.md")
    }

    @Test func excerptCollapsesWhitespace() {
        #expect(StringUtilities.excerpt("a\n\n  b   c", maxLength: 10) == "a b c")
        let long = String(repeating: "x", count: 200)
        #expect(StringUtilities.excerpt(long).count == 161)
        #expect(StringUtilities.excerpt(long).hasSuffix("…"))
    }
}
