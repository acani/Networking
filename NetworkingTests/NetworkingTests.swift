import XCTest
import Networking

class NetworkingTests: XCTestCase {
  func testStrip() {
    XCTAssertEqual("".anw_addingFormURLEncoding, "")
    XCTAssertEqual("Hello, World!".anw_addingFormURLEncoding, "Hello,+World!")
    XCTAssertEqual("🤓😎".anw_addingFormURLEncoding, "%F0%9F%A4%93%F0%9F%98%8E")
    XCTAssertEqual("123".anw_addingFormURLEncoding, "123")
    XCTAssertEqual("abc123*-._?".anw_addingFormURLEncoding, "abc123*-._?")
    XCTAssertEqual("&+=".anw_addingFormURLEncoding, "%26%2B%3D")
  }
}
