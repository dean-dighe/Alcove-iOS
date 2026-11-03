//
//  AlcoveWebSessionTest.swift
//  AmperfyKitTests
//
//  Alcove: the web player's sign-in and setting (AmperfyKit/Api/AlcoveWebSession.swift).
//

@testable import AmperfyKit
import XCTest

class AlcoveWebSessionTest: XCTestCase {
  func testChallengeMatchesRfc7636() {
    // RFC 7636 appendix B
    XCTAssertEqual(
      AlcoveWebSession.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
      "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    )
  }

  func testVerifierIs43Base64urlCharacters() {
    let v = AlcoveWebSession.newVerifier()
    XCTAssertEqual(v.count, 43)
    XCTAssertNotNil(v.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression))
    XCTAssertNotEqual(v, AlcoveWebSession.newVerifier())
  }

  func testSignInUrlAsksForTheIosAppSignIn() {
    let url = AlcoveWebSession.signInURL(challenge: "abc")
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertEqual(url.path, "/auth/login")
    XCTAssertEqual(items.first { $0.name == "client" }?.value, "ios")
    XCTAssertEqual(items.first { $0.name == "challenge" }?.value, "abc")
  }

  func testCallbackCode() {
    let code = String(repeating: "a", count: 43)
    XCTAssertEqual(
      AlcoveWebSession.code(fromCallback: URL(string: "alcove://auth-callback?code=\(code)")!),
      code
    )
    XCTAssertNil(
      AlcoveWebSession
        .code(fromCallback: URL(string: "alcove://auth-callback?code=short")!)
    )
    XCTAssertNil(AlcoveWebSession.code(fromCallback: URL(string: "alcove://other?code=\(code)")!))
    XCTAssertNil(
      AlcoveWebSession
        .code(fromCallback: URL(string: "https://auth-callback?code=\(code)")!)
    )
  }

  func testSessionCookieIsTheHostPrefixedOne() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let c = AlcoveWebSession.cookie(session: "sid", now: now)!
    XCTAssertEqual(c.name, "__Host-alcove_sid")
    XCTAssertEqual(c.value, "sid")
    XCTAssertEqual(c.path, "/")
    XCTAssertTrue(c.isSecure)
    XCTAssertEqual(c.domain, "alcove.netsuite.tech")
    XCTAssertEqual(c.expiresDate, now.addingTimeInterval(30 * 86400))
  }

  func testOnlyAlcovePagesLoadAndItsSignInIsCaught() {
    XCTAssertTrue(AlcoveWebSession.isAlcove(URL(string: "https://alcove.netsuite.tech/listen")!))
    XCTAssertFalse(AlcoveWebSession.isAlcove(URL(string: "http://alcove.netsuite.tech/listen")!))
    XCTAssertFalse(AlcoveWebSession.isAlcove(URL(string: "https://accounts.google.com/")!))
    XCTAssertTrue(
      AlcoveWebSession
        .isSignIn(URL(string: "https://alcove.netsuite.tech/auth/login?next=%2Flisten")!)
    )
    XCTAssertFalse(AlcoveWebSession.isSignIn(URL(string: "https://alcove.netsuite.tech/listen")!))
  }

  func testPlayerInterfaceDefaultsToNativeAndIsKept() {
    let d = UserDefaults(suiteName: "AlcoveWebSessionTest")!
    d.removePersistentDomain(forName: "AlcoveWebSessionTest")
    XCTAssertEqual(AlcovePlayerInterface.read(d), .native)
    AlcovePlayerInterface.write(.web, d)
    XCTAssertEqual(AlcovePlayerInterface.read(d), .web)
    d.set("bogus", forKey: AlcovePlayerInterface.defaultsKey)
    XCTAssertEqual(AlcovePlayerInterface.read(d), .native)
  }
}
