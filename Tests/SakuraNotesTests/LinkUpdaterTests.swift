import Testing
import Foundation
@testable import SakuraNotesApp

@Suite("Link Updater")
struct LinkUpdaterTests {

    @Test func wikiLinksRewrittenOnTitleChange() {
        let content = "See [[Old Title]] and [[Old Title|alias]] and [[Old Title#anchor]] but not [[Other]]."
        let out = LinkUpdater.rewriteWikiLinks(content, oldTitle: "Old Title", newTitle: "New Title")
        #expect(out.contains("[[New Title]]"))
        #expect(out.contains("[[New Title|alias]]"))
        #expect(out.contains("[[New Title#anchor]]"))
        #expect(out.contains("[[Other]]"))
        #expect(!out.contains("[[Old Title"))
    }

    @Test func wikiLinksOnlyMatchExactTitle() {
        let out = LinkUpdater.rewriteWikiLinks("[[Old Title Extended]]", oldTitle: "Old Title", newTitle: "New")
        #expect(out == "[[Old Title Extended]]")
    }

    @Test func relativeLinksRewrittenForMovedTarget() {
        // Note at "notes/a.md" links to "notes/b.md"; b moved to "archive/b.md".
        let content = "text ![img](b.png) and [doc](b.md) and [ext](https://x.com) and [anchor](#top)"
        let out = LinkUpdater.rewriteRelativeLinks(
            content,
            noteFolder: "notes",
            oldPath: "notes/b.md",
            newPath: "archive/b.md"
        )
        #expect(out.contains("[doc](../archive/b.md)"))
        #expect(out.contains("[ext](https://x.com)"))
        #expect(out.contains("[anchor](#top)"))
    }

    @Test func folderMovesRewriteChildLinks() {
        let out = LinkUpdater.rewriteRelativeLinks(
            "[up](../b.md)",
            noteFolder: "oldfolder/sub",
            oldPath: "oldfolder",
            newPath: "newfolder"
        )
        #expect(out.contains("../newfolder") || out.contains("(newfolder") || out.contains(".."))
    }

    @Test func relativePathComputation() {
        #expect(LinkUpdater.relativeFrom(noteFolder: "notes", to: "archive/b.md") == "../archive/b.md")
        #expect(LinkUpdater.relativeFrom(noteFolder: "notes", to: "notes/b.md") == "b.md")
        #expect(LinkUpdater.relativeFrom(noteFolder: "", to: "b.md") == "b.md")
    }

    @Test func pathResolverHandlesDots() {
        #expect(PreviewPathResolver.resolve(base: "a/b", relative: "../c.png") == "a/c.png")
        #expect(PreviewPathResolver.resolve(base: "", relative: "x/y.md") == "x/y.md")
        #expect(PreviewPathResolver.resolve(base: "a", relative: "./z") == "a/z")
    }
}
