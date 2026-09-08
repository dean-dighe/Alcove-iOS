//
//  AlcoveAPI.swift
//  AmperfyKit
//
//  The request and manage endpoints, which are Alcove's own rather than
//  Subsonic's. They live behind the same edge as the web pages and take the
//  same bearer token, so the app and the browser talk to one API.
//
//  Identity is a Supabase access token, which expires. Rather than storing a
//  refresh token, this mints a fresh one from the credentials already held for
//  the media server: the two passwords are kept in step server side, so the
//  one the user signed in with is the one that works here.
//
//  Licensed under GPL-3.0, as the rest of this project is.
//

import Foundation

// MARK: - Models

public struct AlcoveSearchResult: Identifiable, Sendable {
  public let id: String
  public let title: String
  public let uploader: String
  public let duration: Int
  /// True when the library already has this song, under some other title.
  public let owned: Bool
  public let ownedAs: String

  public var durationText: String {
    guard duration > 0 else { return "" }
    return String(format: "%d:%02d", duration / 60, duration % 60)
  }
}

public struct AlcoveRequest: Identifiable, Sendable {
  public let id: String
  public let query: String
  public let status: String
  public let at: String
  public let detail: String
}

public struct AlcoveTrack: Identifiable, Sendable {
  public let id: String
  public let artist: String
  public let title: String
  public let album: String
  /// Path relative to the library root. Playlist membership is keyed by it.
  public let rel: String
  public let playlists: [String]
}

public struct AlcoveLibraryPage: Sendable {
  public let tracks: [AlcoveTrack]
  public let playlists: [String]
  public let total: Int
}

public enum AlcoveAPIError: LocalizedError {
  case notSignedIn
  case unavailable(String)
  case server(String)

  public var errorDescription: String? {
    switch self {
    case .notSignedIn: "Sign in again to continue."
    case let .unavailable(m): m
    case let .server(m): m
    }
  }
}

// MARK: - Session

/// Holds a Supabase access token and mints a new one when it goes stale, for
/// one Amperfy account.
@MainActor
public final class AlcoveSession {
  fileprivate init() {}

  private var token: String?
  private var expiry = Date.distantPast
  private var email = ""
  private var password = ""

  public var isConfigured: Bool { !email.isEmpty && !password.isEmpty }

  /// Called after a successful sign in, and again on launch from stored
  /// credentials. Changing either value drops the cached token.
  public func configure(email: String, password: String) {
    guard email != self.email || password != self.password else { return }
    self.email = email
    self.password = password
    token = nil
    expiry = .distantPast
  }

  public func signOut() {
    email = ""
    password = ""
    token = nil
    expiry = .distantPast
  }

  /// Discard the cached token so the next call mints a fresh one. Used when
  /// the edge rejects a token we believed was still good.
  public func invalidate() {
    token = nil
    expiry = .distantPast
  }

  public func validToken() async throws -> String {
    if let token, Date() < expiry { return token }
    guard isConfigured else { throw AlcoveAPIError.notSignedIn }
    let fresh = try await AlcoveAuth.accessToken(email: email, password: password)
    token = fresh.token
    // Renew a little early rather than discovering expiry mid-request.
    expiry = Date().addingTimeInterval(max(60, fresh.expiresIn - 120))
    return fresh.token
  }
}

/// One AlcoveSession per Amperfy account, keyed by AccountInfo.ident.
///
/// A single shared session used to serve every account: on a device with two
/// signed-in accounts, whichever account's credentials were configured last
/// (via sign-in, or the app's own re-priming on launch) silently answered
/// Alcove API calls for *both* accounts' Request/Manage tabs. Scoping by
/// account keeps them from ever colliding.
@MainActor
public final class AlcoveSessionStore {
  public static let shared = AlcoveSessionStore()
  private init() {}

  private var sessions: [String: AlcoveSession] = [:]

  public func session(for accountId: String) -> AlcoveSession {
    if let existing = sessions[accountId] { return existing }
    let created = AlcoveSession()
    sessions[accountId] = created
    return created
  }

  /// Drop an account's session entirely, e.g. on logout, so a later account
  /// reusing the same slot (unlikely, but AccountInfo.ident is only a hash)
  /// never inherits stale state.
  public func signOut(accountId: String) {
    sessions[accountId]?.signOut()
    sessions.removeValue(forKey: accountId)
  }

  /// UserDefaults key for the Unimatrix email behind one account's session.
  /// Needed alongside the stored Subsonic credentials because the email is
  /// not part of them -- Subsonic only has the derived username.
  public static func emailDefaultsKey(for accountId: String) -> String {
    "alcove.email.\(accountId)"
  }
}

// MARK: - API

public enum AlcoveAPI {
  private static var host: String { AlcoveAuth.host }

  private static func decode(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
  }

  /// One request, retried once against a freshly minted token. The edge
  /// returns 401 both for an expired token and for a revoked licence, and the
  /// two are indistinguishable from here, so a single retry separates them.
  private static func send(
    accountId: String,
    path: String,
    method: String = "GET",
    body: [String: Any]? = nil
  ) async throws -> [String: Any] {
    let session = await AlcoveSessionStore.shared.session(for: accountId)
    var lastMessage = "Alcove is not reachable."
    for attempt in 0 ..< 2 {
      let token = try await session.validToken()
      guard let url = URL(string: host + path) else {
        throw AlcoveAPIError.unavailable("Bad request")
      }
      var req = URLRequest(url: url)
      req.httpMethod = method
      req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
      if let body {
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
      }

      let data: Data
      let http: HTTPURLResponse
      do {
        let (d, resp) = try await URLSession.shared.data(for: req)
        guard let h = resp as? HTTPURLResponse else {
          throw AlcoveAPIError.unavailable(lastMessage)
        }
        data = d
        http = h
      } catch {
        throw AlcoveAPIError.unavailable(lastMessage)
      }

      let json = decode(data)
      if http.statusCode == 200 { return json }

      lastMessage = (json["error"] as? String) ?? "Something went wrong."
      if http.statusCode == 401, attempt == 0 {
        await session.invalidate()
        continue
      }
      if http.statusCode == 401 { throw AlcoveAPIError.notSignedIn }
      throw AlcoveAPIError.server(lastMessage)
    }
    throw AlcoveAPIError.unavailable(lastMessage)
  }

  // MARK: Request tab

  public static func search(_ query: String, accountId: String) async throws
    -> [AlcoveSearchResult] {
    let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    let json = try await send(accountId: accountId, path: "/request/api/search?q=\(q)")
    let rows = json["results"] as? [[String: Any]] ?? []
    return rows.compactMap { r in
      guard let id = r["id"] as? String, let title = r["title"] as? String else { return nil }
      return AlcoveSearchResult(
        id: id,
        title: title,
        uploader: r["uploader"] as? String ?? "",
        duration: r["duration"] as? Int ?? 0,
        owned: r["owned"] as? Bool ?? false,
        ownedAs: r["owned_as"] as? String ?? ""
      )
    }
  }

  public static func queue(query: String, videoId: String, accountId: String) async throws {
    _ = try await send(
      accountId: accountId,
      path: "/request/api/queue",
      method: "POST",
      body: ["query": query, "videoId": videoId]
    )
  }

  public static func myRequests(accountId: String) async throws -> [AlcoveRequest] {
    let json = try await send(accountId: accountId, path: "/request/api/queue")
    let rows = json["requests"] as? [[String: Any]] ?? []
    return rows.compactMap { r in
      guard let id = r["id"] as? String else { return nil }
      return AlcoveRequest(
        id: id,
        query: r["query"] as? String ?? "",
        status: r["status"] as? String ?? "",
        at: r["at"] as? String ?? "",
        detail: r["detail"] as? String ?? ""
      )
    }
  }

  // MARK: Manage tab

  public static func library(
    matching query: String = "",
    accountId: String
  ) async throws -> AlcoveLibraryPage {
    let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    let json = try await send(accountId: accountId, path: "/manage/api/tracks?q=\(q)")
    let rows = json["tracks"] as? [[String: Any]] ?? []
    let tracks = rows.compactMap { r -> AlcoveTrack? in
      guard let id = r["id"] as? String else { return nil }
      return AlcoveTrack(
        id: id,
        artist: r["artist"] as? String ?? "",
        title: r["title"] as? String ?? "",
        album: r["album"] as? String ?? "",
        rel: r["rel"] as? String ?? "",
        playlists: r["playlists"] as? [String] ?? []
      )
    }
    return AlcoveLibraryPage(
      tracks: tracks,
      playlists: json["playlists"] as? [String] ?? [],
      total: json["total"] as? Int ?? tracks.count
    )
  }

  public static func edit(
    id: String,
    title: String,
    artist: String,
    album: String,
    accountId: String
  ) async throws {
    _ = try await send(
      accountId: accountId,
      path: "/manage/api/edit",
      method: "POST",
      body: ["id": id, "title": title, "artist": artist, "album": album]
    )
  }

  public static func setMembership(
    rels: [String],
    addTo: String? = nil,
    removeFrom: String? = nil,
    accountId: String
  ) async throws {
    _ = try await send(
      accountId: accountId,
      path: "/manage/api/membership",
      method: "POST",
      body: [
        "rels": rels,
        "add": addTo.map { [$0] } ?? [],
        "remove": removeFrom.map { [$0] } ?? [],
      ]
    )
  }

  public static func playlist(
    action: String,
    name: String,
    newName: String = "",
    accountId: String
  ) async throws {
    _ = try await send(
      accountId: accountId,
      path: "/manage/api/playlist",
      method: "POST",
      body: ["action": action, "name": name, "newName": newName]
    )
  }
}
