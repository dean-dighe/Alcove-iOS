//
//  AlcoveWebSession.swift
//  AmperfyKit
//
//  Alcove: the web player (alcove.netsuite.tech/listen) inside the app, Dean 2026-11-03. The page is Alcove's own: the
//  iPod or the standard player, chosen per person on the server. It is signed in as the app account (the app's own
//  token becomes an Alcove session at POST /auth/app-session, set as the page's __Host-alcove_sid cookie), and it
//  plays through the app's player (window.AlcovePlayer, AlcovePlayerBridge below).
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation
import WebKit

// MARK: - AlcovePlayerInterface

/// Which player the app shows: Amperfy's own screens, or Alcove's web player.
public enum AlcovePlayerInterface: String, CaseIterable, Sendable {
  case native
  case web

  public static let defaultsKey = "alcove.playerInterface"
  /// Posted when the choice changes, so the tab bar can add or remove the web player.
  public static let changed = Notification.Name("alcove.playerInterface.changed")

  public var title: String {
    switch self {
    case .native: "Native"
    case .web: "Web (iPod or standard)"
    }
  }

  public static func read(_ defaults: UserDefaults = .standard) -> AlcovePlayerInterface {
    AlcovePlayerInterface(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .native
  }

  public static func write(_ value: AlcovePlayerInterface, _ defaults: UserDefaults = .standard) {
    defaults.set(value.rawValue, forKey: defaultsKey)
    NotificationCenter.default.post(name: changed, object: nil)
  }
}

// MARK: - AlcoveWebSession

public enum AlcoveWebSession {
  public static let cookieName = "__Host-alcove_sid"
  /// The Worker keeps an app session 7 days (APP_SESSION_TTL_S in worker/src/auth.js).
  public static let sessionLifetime: TimeInterval = 7 * 86400

  public static var hostURL: URL { URL(string: AlcoveAuth.host)! }
  public static var playerURL: URL { hostURL.appendingPathComponent("listen") }

  /// Only Alcove's own pages load in the player; anything else opens outside it.
  public static func isAlcove(_ url: URL) -> Bool {
    url.scheme == "https" && url.host == hostURL.host
  }

  /// The page's sign-in link (`/auth/login`, from either interface): the app signs the page in as its own account
  /// instead (Google refuses sign-in inside a web view, and the app account is the one to use).
  public static func isSignIn(_ url: URL) -> Bool {
    isAlcove(url) && url.path == "/auth/login"
  }

  /// The page's session cookie. `__Host-` needs Secure, Path=/ and no Domain attribute, so it is host-only.
  public static func cookie(session: String, now: Date = Date()) -> HTTPCookie? {
    HTTPCookie(properties: [
      .name: cookieName,
      .value: session,
      .originURL: hostURL,
      .path: "/",
      .secure: "TRUE",
      .expires: now.addingTimeInterval(sessionLifetime),
      .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax,
    ])
  }

  /// Forget the web player's session (an app sign-out): the page asks to sign in again next time.
  @MainActor
  public static func clearCookies(in store: WKHTTPCookieStore) async {
    for c in await store.allCookies() where c.name == cookieName { await store.deleteCookie(c) }
  }
}

// MARK: - App account session

extension AlcoveWebSession {
  /// POST /auth/app-session with the app account's own Supabase token (the bearer its Request and Manage tabs send):
  /// the web player's session for that same account (Alcove `worker/src/auth.js`, 7 days).
  public static func appSession(token: String) async throws -> String {
    var req = URLRequest(url: hostURL.appendingPathComponent("auth/app-session"))
    req.httpMethod = "POST"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    let (data, resp) = try await URLSession.shared.data(for: req)
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard let http = resp as? HTTPURLResponse else { throw AlcoveAuthError.unreachable }
    if http.statusCode == 200, let session = json["session"] as? String,
       !session.isEmpty { return session }
    if http.statusCode == 403 { throw AlcoveAuthError.notLicensed }
    throw AlcoveAuthError.badCredentials((json["error"] as? String) ?? "Sign in to the app again.")
  }
}

// MARK: - AlcovePlayerBridge

/// `window.AlcovePlayer` for the web player, the contract the Android app gives the same page
/// (claude-imessage android/.../music/IpodBridge.kt): with it both interfaces drive the app's own player, so the lock
/// screen, background play and CarPlay work. Calls come in as script messages; `state()` must answer at once, so the
/// app pushes the player's snapshot into the page (`window.__alcoveState`) and the shim returns the last one.
public enum AlcovePlayerBridge {
  public static let handlerName = "alcovePlayer"
  public static let emptyState =
    #"{"playing":false,"loading":false,"time":0,"duration":0,"index":0,"ids":[]}"#

  public static let shimSource = """
  (function () {
    var last = '\(emptyState)';
    var post = function (m) { window.webkit.messageHandlers.\(handlerName).postMessage(m); };
    window.__alcoveState = function (s) { last = s; };
    window.AlcovePlayer = {
      load: function (j) { post({ op: 'load', json: j }); },
      enqueue: function (j, next) { post({ op: 'enqueue', json: j, next: !!next }); },
      toggle: function () { post({ op: 'toggle' }); },
      pause: function () { post({ op: 'pause' }); },
      next: function () { post({ op: 'next' }); },
      previous: function () { post({ op: 'previous' }); },
      seek: function (s) { post({ op: 'seek', value: Number(s) || 0 }); },
      setVolume: function (v) { post({ op: 'volume', value: Number(v) || 0 }); },
      setRepeat: function (m) { post({ op: 'repeat', mode: String(m) }); },
      setShuffle: function (on) { post({ op: 'shuffle', on: !!on }); },
      stop: function () { post({ op: 'stop' }); },
      reauth: function () { post({ op: 'reauth' }); },
      state: function () { return last; }
    };
  })();
  """

  public struct Item: Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    public var art: String
    public var seconds: Int

    public init(
      id: String,
      title: String = "",
      artist: String = "",
      album: String = "",
      art: String = "",
      seconds: Int = 0
    ) {
      self.id = id
      self.title = title
      self.artist = artist
      self.album = album
      self.art = art
      self.seconds = seconds
    }

    var json: [String: Any] {
      ["id": id, "title": title, "artist": artist, "album": album, "art": art, "seconds": seconds]
    }
  }

  /// The page's `{index, queue: [{id, title, artist, album, art, seconds}]}`; nil when it is not that or is empty.
  /// The index is kept inside the queue.
  public static func parseQueue(_ json: String) -> (items: [Item], index: Int)? {
    guard let o = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
          let q = o["queue"] as? [[String: Any]] else { return nil }
    let items = q.compactMap { s -> Item? in
      guard let id = s["id"] as? String, !id.isEmpty else { return nil }
      return Item(
        id: id,
        title: s["title"] as? String ?? "",
        artist: s["artist"] as? String ?? "",
        album: s["album"] as? String ?? "",
        art: s["art"] as? String ?? "",
        seconds: (s["seconds"] as? NSNumber)?.intValue ?? 0
      )
    }
    guard !items.isEmpty else { return nil }
    let index = (o["index"] as? NSNumber)?.intValue ?? 0
    return (items, min(max(index, 0), items.count - 1))
  }

  /// The page's repeat word as the player's mode.
  public static func repeatMode(_ word: String) -> RepeatMode {
    switch word {
    case "one": .single
    case "all": .all
    default: .off
    }
  }

  /// The snapshot as the page reads it: seconds, the queue's ids and where the current song is in them.
  public static func stateJSON(
    playing: Bool,
    time: Double,
    duration: Double,
    ids: [String],
    index: Int,
    current: Item?
  )
    -> String {
    var o: [String: Any] = [
      "playing": playing, "loading": false, "time": time.isFinite ? time : 0,
      "duration": duration.isFinite ? duration : 0, "index": index, "ids": ids,
    ]
    if let current { o["current"] = current.json }
    let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ??
      Data(emptyState.utf8)
    return String(decoding: data, as: UTF8.self)
  }

  /// `window.__alcoveState(<the state as a JavaScript string>)`, safe for any text in it.
  public static func pushScript(state: String) -> String {
    let literal = (try? JSONSerialization.data(
      withJSONObject: [state],
      options: [.fragmentsAllowed]
    ))
    .map { String(decoding: $0, as: UTF8.self) } ?? "[\"\"]"
    return "window.__alcoveState && window.__alcoveState(\(literal)[0]);"
  }
}
