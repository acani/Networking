import XCTest
import Networking

class NetworkingTests: XCTestCase {
  func testStrip() {
    XCTAssertEqual("".anw_addingFormURLEncoding, "")                               // empty
    XCTAssertEqual("Hello, World!".anw_addingFormURLEncoding, "Hello%2C+World%21") // spaces & punctuation
    XCTAssertEqual("🤓😎".anw_addingFormURLEncoding, "🤓😎")                      // emojis
    XCTAssertEqual("123".anw_addingFormURLEncoding, "123")                         // numeric
    XCTAssertEqual("abc123*-._".anw_addingFormURLEncoding, "abc123*-._")           // mixed
  }
}
