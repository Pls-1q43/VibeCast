import XCTest
@testable import VibeCast

final class TextWriterTests: XCTestCase {

    func testEditorInsertionStateUsesUTF16Length() {
        XCTAssertEqual(TextWriter.utf16Length("abc"), 3)
        XCTAssertEqual(TextWriter.utf16Length("你好"), 2)
        XCTAssertEqual(TextWriter.utf16Length("a🙂b"), 4)
    }

    func testEditorInsertionStateDefaultsToSelectedRange() {
        let state = EditorInsertionState(location: 7, length: 3, text: "abc")

        XCTAssertEqual(state.strategy, .selectedRange)
        XCTAssertEqual(state.location, 7)
        XCTAssertEqual(state.length, 3)
        XCTAssertEqual(state.text, "abc")
    }

    func testUndoPasteStateUsesUTF16Length() {
        let state = EditorInsertionState.undoPaste(text: "a🙂b")

        XCTAssertEqual(state.strategy, .undoPaste)
        XCTAssertEqual(state.location, 0)
        XCTAssertEqual(state.length, 4)
        XCTAssertEqual(state.text, "a🙂b")
    }
}
