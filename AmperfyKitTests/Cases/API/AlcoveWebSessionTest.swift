//
//  AlcoveWebSessionTest.swift
//  AmperfyKitTests
//
//  Alcove: the web player's session cookie, setting and native bridge (AmperfyKit/Api/AlcoveWebSession.swift).
//

@testable import AmperfyKit
import XCTest

// MARK: - AlcoveWebSessionTest

class AlcoveWebSessionTest: XCTestCase {
  func testSessionCookieIsTheHostPrefixedOne() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let c = AlcoveWebSession.cookie(session: "sid", now: now)!
    XCTAssertEqual(c.name, "__Host-alcove_sid")
    XCTAssertEqual(c.value, "sid")
    XCTAssertEqual(c.path, "/")
    XCTAssertTrue(c.isSecure)
    XCTAssertEqual(c.domain, "alcove.netsuite.tech")
    XCTAssertEqual(c.expiresDate, now.addingTimeInterval(86400))
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

// MARK: - AlcovePlayerBridgeTest

class AlcovePlayerBridgeTest: XCTestCase {
  func testQueueParsesLikeTheAndroidBridge() {
    let json =
      #"{"index":5,"queue":[{"id":"t1","title":"A","artist":"B","album":"C","art":"al1","seconds":200},{"id":"t2"},{"title":"no id"}]}"#
    let (items, index) = AlcovePlayerBridge.parseQueue(json)!
    XCTAssertEqual(items.map(\.id), ["t1", "t2"])
    XCTAssertEqual(
      items[0],
      AlcovePlayerBridge.Item(
        id: "t1",
        title: "A",
        artist: "B",
        album: "C",
        art: "al1",
        seconds: 200
      )
    )
    XCTAssertEqual(index, 1, "the index stays inside the queue")
    XCTAssertNil(AlcovePlayerBridge.parseQueue(#"{"queue":[]}"#))
    XCTAssertNil(AlcovePlayerBridge.parseQueue("not json"))
  }

  func testStartIndexAmongTheSongsFound() {
    XCTAssertEqual(AlcovePlayerBridge.startIndex(found: [true, true, true], asked: 2), 2)
    XCTAssertEqual(
      AlcovePlayerBridge.startIndex(found: [true, false, true], asked: 2),
      1,
      "a missing song before shifts it"
    )
    XCTAssertEqual(
      AlcovePlayerBridge.startIndex(found: [true, false, true], asked: 1),
      1,
      "a missing asked-for song starts at the next found"
    )
    XCTAssertEqual(AlcovePlayerBridge.startIndex(found: [true, true, false], asked: 2), 0)
    XCTAssertNil(AlcovePlayerBridge.startIndex(found: [false, false], asked: 0))
  }

  func testEachAccountHasItsOwnWebStore() {
    let a = AlcoveWebSession.storeIdentifier(accountId: "a")
    XCTAssertEqual(a, AlcoveWebSession.storeIdentifier(accountId: "a"))
    XCTAssertNotEqual(a, AlcoveWebSession.storeIdentifier(accountId: "b"))
  }

  func testRepeatWords() {
    XCTAssertEqual(AlcovePlayerBridge.repeatMode("one"), .single)
    XCTAssertEqual(AlcovePlayerBridge.repeatMode("all"), .all)
    XCTAssertEqual(AlcovePlayerBridge.repeatMode("off"), .off)
    XCTAssertEqual(AlcovePlayerBridge.repeatMode("x"), .off)
  }

  func testStateIsWhatThePagePolls() throws {
    let s = AlcovePlayerBridge.stateJSON(
      playing: true, time: 12.5, duration: .nan, ids: ["a", "b"], index: 1,
      current: .init(id: "b", title: "T", artist: "R", album: "L", art: "x", seconds: 90)
    )
    let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    XCTAssertEqual(o["playing"] as? Bool, true)
    XCTAssertEqual(o["time"] as? Double, 12.5)
    XCTAssertEqual(o["duration"] as? Double, 0, "a duration not known yet is 0, not NaN")
    XCTAssertEqual(o["ids"] as? [String], ["a", "b"])
    XCTAssertEqual(o["index"] as? Int, 1)
    XCTAssertEqual((o["current"] as? [String: Any])?["title"] as? String, "T")
  }

  func testPushScriptQuotesAnything() {
    let script = AlcovePlayerBridge.pushScript(state: #"{"t":"it's \"x\" </script>"}"#)
    XCTAssertTrue(script.hasPrefix("window.__alcoveState && window.__alcoveState(["))
    XCTAssertFalse(
      script.contains("it's \"x\""),
      "the state is a JSON string literal, not raw text"
    )
  }

  func testShimDefinesTheWholeContract() {
    for name in [
      "load",
      "enqueue",
      "toggle",
      "pause",
      "next",
      "previous",
      "seek",
      "setVolume",
      "setRepeat",
      "setShuffle",
      "stop",
      "reauth",
      "state",
    ] {
      XCTAssertTrue(AlcovePlayerBridge.shimSource.contains("\(name): function"), name)
    }
  }
}
