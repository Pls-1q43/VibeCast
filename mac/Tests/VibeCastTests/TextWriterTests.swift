import XCTest
@testable import VibeCast

final class TextWriterTests: XCTestCase {

    func testEditorInsertionStateUsesUTF16Length() {
        XCTAssertEqual(TextWriter.utf16Length("abc"), 3)
        XCTAssertEqual(TextWriter.utf16Length("你好"), 2)
        XCTAssertEqual(TextWriter.utf16Length("a🙂b"), 4)
    }
}
