import XCTest
import LearningCore

final class SafeCardMarkupTests: XCTestCase {
    func testNestedFormattingAndParagraphsPreserveReadableContent() throws {
        let document = SafeCardMarkup.inspect("<p>A <b>bold <i>and italic</i></b> answer.</p><div>Next<br>line <u>underlined</u>.</div>")
        XCTAssertTrue(document.isSupported, document.findings.joined(separator: "; "))
        XCTAssertEqual(document.plainText, "A bold and italic answer.\nNext\nline underlined.")
        let runs = document.blocks.flatMap { block -> [SafeCardRun] in if case .text(let runs) = block { return runs }; return [] }
        XCTAssertTrue(runs.contains { $0.text == "and italic" && $0.style.contains([.bold, .italic]) })
        XCTAssertTrue(runs.contains { $0.text == "underlined" && $0.style.contains(.underline) })
    }
    func testLocalMediaEntitiesAndAudioReferences() {
        let document = SafeCardMarkup.inspect("See <img src=\"cell &amp; nucleus.png\" alt=\"Cell > nucleus\">[sound:pronunciation.mp3]")
        XCTAssertTrue(document.isSupported, document.findings.joined(separator: "; "))
        XCTAssertEqual(document.mediaNames, ["cell & nucleus.png", "pronunciation.mp3"])
        XCTAssertTrue(document.blocks.contains(.image(name: "cell & nucleus.png", alternative: "Cell > nucleus")))
        XCTAssertTrue(document.blocks.contains(.audio(name: "pronunciation.mp3")))
    }
    func testEscapedTagsRemainLiteralTextNotInstructions() {
        let document = SafeCardMarkup.inspect("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &#x1F9E0; &#233; &nbsp;")
        XCTAssertTrue(document.isSupported, document.findings.joined(separator: "; "))
        XCTAssertEqual(document.plainText, "<script>alert(\"x\")</script> & 🧠 é \u{00a0}")
        XCTAssertTrue(document.mediaNames.isEmpty)
    }
    func testScriptStyleExternalLoadsAndUnexpectedAttributesAreUnsupported() {
        for text in ["<script>alert(1)</script>", "<iframe src='page'></iframe>", "<img src='https://example.com/a.png'>", "<img src='//example.com/a.png'>", "<img src='data:image/png;base64,AA=='>", "<img src='a.png' onerror='alert(1)'>", "<span style='display:none'>hidden</span>", "<a href='https://example.com'>link</a>", "<svg></svg>", "<style>b{color:red}</style>"] {
            XCTAssertFalse(SafeCardMarkup.inspect(text).isSupported, text)
        }
    }
    func testMalformedAndNestedMismatchedMarkupIsReported() {
        for text in ["<b>missing end", "<b><i>wrong</b></i>", "<img src='unterminated>", "<img>", "[sound:unfinished", "<div bogus>x</div>", "<img src='a.png' src='b.png'>"] {
            XCTAssertFalse(SafeCardMarkup.inspect(text).isSupported, text)
        }
    }
    func testPathTraversalAndUnsupportedMediaCannotReachRenderer() {
        for reference in ["../escape.png", "..\\escape.png", "file:///tmp/private.png", "C:\\private.png", "%2e%2e%2fescape.png", "javascript:alert(1)", "vector.svg"] {
            XCTAssertFalse(SafeCardMarkup.inspect("<img src='\(reference)'>").isSupported, reference)
        }
        XCTAssertFalse(SafeCardMarkup.inspect("[sound:https://example.com/a.mp3]").isSupported)
        XCTAssertFalse(SafeCardMarkup.inspect("[sound:unplayable.ogg]").isSupported)
    }
    func testPlainMathUnicodeAndLineBreaksRemainReadable() {
        let text = "2 < 3 and 5 > 4.\n東京 → Sydney. {{c1::answer}}"
        let document = SafeCardMarkup.inspect(text)
        XCTAssertTrue(document.isSupported, document.findings.joined(separator: "; "))
        XCTAssertEqual(document.plainText, text)
    }
    func testUnknownEntitiesAndComplexMarkupHaveExplicitFindings() {
        XCTAssertFalse(SafeCardMarkup.inspect("&notASupportedEntity;").isSupported)
        XCTAssertFalse(SafeCardMarkup.inspect(String(repeating: "x", count: 1_000_001)).isSupported)
        XCTAssertFalse(SafeCardMarkup.inspect(String(repeating: "<b>", count: 300)).isSupported)
    }
    func testPreformattedCodeAndStrikethroughAreSupported() {
        let document = SafeCardMarkup.inspect("<pre><code>let x = 2\n  x + 1</code></pre><s>old</s><span>new</span>")
        XCTAssertTrue(document.isSupported, document.findings.joined(separator: "; "))
        XCTAssertEqual(document.plainText, "let x = 2\n  x + 1\noldnew")
    }
}
