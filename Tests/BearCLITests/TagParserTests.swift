import XCTest
@testable import BearCLICore

final class TagParserExtractTests: XCTestCase {

    func testSimpleTag() {
        XCTAssertEqual(TagParser.extractTags(from: "#foo"), ["foo"])
    }

    func testTagAfterText() {
        XCTAssertEqual(
            TagParser.extractTags(from: "hello #foo world"),
            ["foo"]
        )
    }

    func testHierarchicalTag() {
        XCTAssertEqual(
            TagParser.extractTags(from: "see #parent/child here"),
            ["parent/child"]
        )
    }

    func testMultipleTags() {
        XCTAssertEqual(
            TagParser.extractTags(from: "#a #b #c"),
            ["a", "b", "c"]
        )
    }

    func testMultiWordTag() {
        XCTAssertEqual(
            TagParser.extractTags(from: "tag this: #multi word tag# done"),
            ["multi word tag"]
        )
    }

    func testSkipsHeadingLines() {
        let text = """
        # My Title
        ## Subheading
        body with #real_tag here
        """
        XCTAssertEqual(TagParser.extractTags(from: text), ["real_tag"])
    }

    func testSkipsFencedCode() {
        let text = """
        outside #keep_me
        ```
        #not_a_tag
        ```
        after #also_keep
        """
        XCTAssertEqual(TagParser.extractTags(from: text), ["keep_me", "also_keep"])
    }

    func testSkipsTildeFence() {
        let text = """
        ~~~
        #nope
        ~~~
        #yes
        """
        XCTAssertEqual(TagParser.extractTags(from: text), ["yes"])
    }

    func testSkipsInlineCode() {
        let text = "code `#inline_nope` and #outside_yes"
        XCTAssertEqual(TagParser.extractTags(from: text), ["outside_yes"])
    }

    func testURLFragmentNotATag() {
        // '#' inside URL is not preceded by whitespace.
        let text = "see https://example.com/page#frag for #realtag"
        XCTAssertEqual(TagParser.extractTags(from: text), ["realtag"])
    }

    func testDoubleHashNotATag() {
        // '##' is a heading when line-start; inline '##' without space after is not a valid tag.
        XCTAssertEqual(TagParser.extractTags(from: "foo ##bar"), [])
    }

    func testTrailingPunctuationStripped() {
        XCTAssertEqual(
            TagParser.extractTags(from: "A #foo, and #bar."),
            ["foo", "bar"]
        )
    }

    func testDeduplicates() {
        XCTAssertEqual(
            TagParser.extractTags(from: "#foo and again #foo"),
            ["foo"]
        )
    }

    func testEmptyAfterHash() {
        XCTAssertEqual(TagParser.extractTags(from: "lonely #"), [])
    }

    func testSkipsFrontMatter() {
        let text = """
        ---
        project: #not_a_tag
        status: draft
        ---
        body #real_tag here
        """
        XCTAssertEqual(TagParser.extractTags(from: text), ["real_tag"])
    }

    func testFrontMatterOnlyAtDocStart() {
        // `---` appearing later in the doc must not start a frontmatter block.
        let text = """
        body intro
        ---
        #tag_between_rules
        ---
        """
        XCTAssertEqual(TagParser.extractTags(from: text), ["tag_between_rules"])
    }

    func testReprodFromIssue20() {
        // `bear_create_note(body: "#repro_tag_1\nhello")`
        XCTAssertEqual(
            TagParser.extractTags(from: "#repro_tag_1\nhello"),
            ["repro_tag_1"]
        )
    }
}

final class TagParserAncestorsTests: XCTestCase {

    func testExpandFlatTag() {
        XCTAssertEqual(TagParser.expandAncestors(["foo"]), ["foo"])
    }

    func testExpandTwoLevel() {
        XCTAssertEqual(
            TagParser.expandAncestors(["parent/child"]),
            ["parent/child", "parent"]
        )
    }

    func testExpandThreeLevel() {
        XCTAssertEqual(
            TagParser.expandAncestors(["a/b/c"]),
            ["a/b/c", "a/b", "a"]
        )
    }

    func testExpandDeduplicates() {
        XCTAssertEqual(
            TagParser.expandAncestors(["a/b", "a/c"]),
            ["a/b", "a", "a/c"]
        )
    }

    func testLeafTagsFiltersAncestors() {
        XCTAssertEqual(
            TagParser.leafTags(["parent", "parent/child"]),
            ["parent/child"]
        )
    }

    func testLeafTagsKeepsSiblings() {
        let input = ["a/b", "a/c", "a"]
        XCTAssertEqual(Set(TagParser.leafTags(input)), Set(["a/b", "a/c"]))
    }

    func testLeafTagsFlat() {
        XCTAssertEqual(TagParser.leafTags(["foo", "bar"]), ["foo", "bar"])
    }
}

final class TagParserRemoveTests: XCTestCase {

    func testRemoveFlatTag() {
        XCTAssertEqual(
            TagParser.remainingTagsAfterRemoval(from: ["foo", "bar"], removing: "foo"),
            ["bar"]
        )
    }

    func testRemoveTagNotPresentIsNoOp() {
        XCTAssertEqual(
            TagParser.remainingTagsAfterRemoval(from: ["foo", "bar"], removing: "baz"),
            ["foo", "bar"]
        )
    }

    func testRemoveLeafDropsAllOrphanedAncestors() {
        // The Issue A regression. Before the deep→shallow walk, this returned
        // `["a"]`: when ancestor `a` was evaluated, `a/b` was still present so
        // `a` was kept; then `a/b` was removed but `a` was never re-checked.
        XCTAssertEqual(
            TagParser.remainingTagsAfterRemoval(
                from: ["a/b/c", "a/b", "a"], removing: "a/b/c"
            ),
            []
        )
    }

    func testRemoveLeafKeepsAncestorWhenSiblingSurvives() {
        // `a/d` is a descendant of `a`, so `a` must survive the cleanup when
        // `a/b/c` (and its unique ancestor `a/b`) are removed.
        XCTAssertEqual(
            TagParser.remainingTagsAfterRemoval(
                from: ["a/b/c", "a/b", "a", "a/d"], removing: "a/b/c"
            ),
            ["a", "a/d"]
        )
    }

    func testRemoveTwoLevelLeaf() {
        XCTAssertEqual(
            TagParser.remainingTagsAfterRemoval(
                from: ["parent/child", "parent"], removing: "parent/child"
            ),
            []
        )
    }

    func testRemoveMiddleOfHierarchy() {
        // Removing `a/b` when `a/b/c` is still indexed should leave the leaf
        // and its required ancestor chain intact.
        XCTAssertEqual(
            TagParser.remainingTagsAfterRemoval(
                from: ["a/b/c", "a/b", "a"], removing: "a/b"
            ),
            ["a/b/c", "a"]
        )
    }

    func testRemovePreservesInputOrder() {
        XCTAssertEqual(
            TagParser.remainingTagsAfterRemoval(
                from: ["zeta", "a/b", "a", "middle"], removing: "a/b"
            ),
            ["zeta", "middle"]
        )
    }
}

final class TagParserStripTests: XCTestCase {

    func testStripSimpleTag() {
        XCTAssertEqual(
            TagParser.stripTag(from: "hello #foo world", name: "foo"),
            "hello world"
        )
    }

    func testStripWholeTagLine() {
        let input = "# Title\n#foo\nbody"
        XCTAssertEqual(
            TagParser.stripTag(from: input, name: "foo"),
            "# Title\nbody"
        )
    }

    func testStripDoesNotTruncateChildTag() {
        XCTAssertEqual(
            TagParser.stripTag(from: "has #parent/child here", name: "parent"),
            "has #parent/child here"
        )
    }

    func testStripHierarchicalTag() {
        XCTAssertEqual(
            TagParser.stripTag(from: "has #parent/child here", name: "parent/child"),
            "has here"
        )
    }

    func testStripMultiWordTag() {
        XCTAssertEqual(
            TagParser.stripTag(from: "a #multi word# b", name: "multi word"),
            "a b"
        )
    }

    func testStripAncestorOnNoteWithOnlyChild() {
        // Removing `parent` when only `#parent/child` is in the body → no change.
        let input = "body #parent/child more"
        XCTAssertEqual(
            TagParser.stripTag(from: input, name: "parent"),
            "body #parent/child more"
        )
    }
}

final class TagParserRenamePrefixTests: XCTestCase {

    func testRenameSimple() {
        XCTAssertEqual(
            TagParser.renameTagPrefix(in: "see #context here", from: "context", to: "10-projects"),
            "see #10-projects here"
        )
    }

    func testRenameWithSubtag() {
        XCTAssertEqual(
            TagParser.renameTagPrefix(in: "tag #context/research yes", from: "context", to: "10-projects"),
            "tag #10-projects/research yes"
        )
    }

    func testRenameDeepSubtag() {
        XCTAssertEqual(
            TagParser.renameTagPrefix(in: "#context/a/b end", from: "context", to: "new"),
            "#new/a/b end"
        )
    }

    func testRenameDoesNotMatchSubstring() {
        // `#contexts` is a different tag (continues into `s`), must not rename.
        XCTAssertEqual(
            TagParser.renameTagPrefix(in: "x #contexts y", from: "context", to: "new"),
            "x #contexts y"
        )
    }

    func testRenameTrailingPunctuation() {
        XCTAssertEqual(
            TagParser.renameTagPrefix(in: "tag #context, done", from: "context", to: "new"),
            "tag #new, done"
        )
    }

    func testRenameNoOpWhenSame() {
        XCTAssertEqual(
            TagParser.renameTagPrefix(in: "#context here", from: "context", to: "context"),
            "#context here"
        )
    }

    func testRenameMultipleOccurrences() {
        let input = "#context top\n- #context/sub\n- #other"
        let expected = "#new top\n- #new/sub\n- #other"
        XCTAssertEqual(
            TagParser.renameTagPrefix(in: input, from: "context", to: "new"),
            expected
        )
    }
}
