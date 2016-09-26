import XCTest
import Networking

class NetworkingTests: XCTestCase {
    func testStrip() {
        XCTAssertEqual("".acn_addingFormURLEncoding, "")                               // empty
        XCTAssertEqual("Hello, World!".acn_addingFormURLEncoding, "Hello%2C+World%21") // spaces & punctuation
        XCTAssertEqual("🤓😎".acn_addingFormURLEncoding, "🤓😎")                      // emojis
        XCTAssertEqual("123".acn_addingFormURLEncoding, "123")                         // numeric
        XCTAssertEqual("abc123*-._".acn_addingFormURLEncoding, "abc123*-._")           // mixed
    }
}
