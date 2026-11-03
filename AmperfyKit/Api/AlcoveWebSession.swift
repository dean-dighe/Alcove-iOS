//
//  AlcoveWebSession.swift
//  AmperfyKit
//
//  Alcove: the web player (alcove.netsuite.tech/listen) inside the app, Dean 2026-11-03. The page is Alcove's own: the
//  iPod or the standard player, chosen per person on the server. It signs in like the Android app's WebView: Google
//  through Alcove's app sign-in (/auth/login?client=ios with a PKCE challenge, alcove://auth-callback?code=, then
//  POST /auth/exchange), and the Alcove session it gets is the page's __Host-alcove_sid cookie.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import CryptoKit
import Foundation

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
  /// The Worker keeps a session 30 days (SESSION_TTL_S in worker/src/auth.js).
  public static let sessionLifetime: TimeInterval = 30 * 86400
  public static let callbackScheme = "alcove"

  public static var hostURL: URL { URL(string: AlcoveAuth.host)! }
  public static var playerURL: URL { hostURL.appendingPathComponent("listen") }

  /// Only Alcove's own pages load in the player; anything else opens outside it.
  public static func isAlcove(_ url: URL) -> Bool {
    url.scheme == "https" && url.host == hostURL.host
  }

  /// The page's sign-in link (`/auth/login`, from either interface). Google refuses sign-in inside a web view, so the
  /// app runs it in the system's sign-in sheet instead.
  public static func isSignIn(_ url: URL) -> Bool {
    isAlcove(url) && url.path == "/auth/login"
  }

  static func base64url(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// A PKCE verifier: 32 random bytes, 43 base64url characters (the Worker accepts 43 to 128).
  public static func newVerifier() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    for i in bytes.indices { bytes[i] = UInt8.random(in: 0 ... 255) }
    return base64url(Data(bytes))
  }

  /// The S256 challenge for a verifier (RFC 7636), as the Worker's pkceChallenge computes it.
  public static func challenge(for verifier: String) -> String {
    base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
  }

  public static func signInURL(challenge: String) -> URL {
    var c = URLComponents(
      url: hostURL.appendingPathComponent("auth/login"),
      resolvingAgainstBaseURL: false
    )!
    c.queryItems = [
      URLQueryItem(name: "client", value: "ios"),
      URLQueryItem(name: "challenge", value: challenge),
      URLQueryItem(name: "select", value: "1"),
    ]
    return c.url!
  }

  /// The one-time code from `alcove://auth-callback?code=...`, or nil for anything else.
  public static func code(fromCallback url: URL) -> String? {
    guard url.scheme == callbackScheme, url.host == "auth-callback" else { return nil }
    let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first(where: { $0.name == "code" })?.value ?? ""
    return code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil ? code : nil
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

  /// POST /auth/exchange {code, verifier} -> the Alcove session.
  public static func exchange(code: String, verifier: String) async throws -> String {
    var req = URLRequest(url: hostURL.appendingPathComponent("auth/exchange"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "verifier": verifier])
    let (data, resp) = try await URLSession.shared.data(for: req)
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard let http = resp as? HTTPURLResponse else { throw AlcoveAuthError.unreachable }
    if http.statusCode == 200, let session = json["session"] as? String,
       !session.isEmpty { return session }
    throw AlcoveAuthError
      .badCredentials((json["error"] as? String) ?? "Sign-in did not finish. Try again.")
  }
}
