//
//  AlcoveAuth.swift
//  AmperfyKit
//
//  Sign in with a Unimatrix account instead of a server URL, username and
//  password typed by hand.
//
//  The three fields the Subsonic backend needs are derived rather than asked
//  for. Identity is Supabase; the music server has its own username but the
//  same password, kept in step by the password sync on the server side. So one
//  email and password produce everything.
//
//      email + password ──> Supabase          access token
//                      └──> GET /api/me       the Subsonic username
//                      └──> LoginCredentials  server, username, password
//
//  Licensed under GPL-3.0, as the rest of this project is.
//

import Foundation

public enum AlcoveAuthError: LocalizedError {
  case badCredentials(String)
  case notLicensed
  case noAccount
  case unreachable

  public var errorDescription: String? {
    switch self {
    case let .badCredentials(msg): msg
    case .notLicensed: "This account is not licensed for Alcove."
    case .noAccount: "No music account yet. Ask for access, then try again."
    case .unreachable: "Could not reach Alcove. Check your connection."
    }
  }
}

public enum AlcoveAuth {
  /// The service this app talks to. Both hostnames resolve to it; the second
  /// predates the rename and is kept so older installs keep working.
  public static let host = "https://alcove.netsuite.tech"

  /// Identity provider. The anon key is a public client key by design: it
  /// permits nothing on its own, every call is still authorised server side.
  public static let supabaseUrl = "https://rqpinbrvjgpzzhmirznv.supabase.co"
  public static let supabaseAnonKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJxcGluYnJ2amdwenpobWlyem52Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgxOTQ0NzYsImV4cCI6MjA5Mzc3MDQ3Nn0.qGCykuITr8cX_kT6OBrxEd3Iyke7i3GrWeV_TzjYbEo"

  private static func post(_ url: URL, body: Data, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.httpBody = body
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw AlcoveAuthError.unreachable }
    return (data, http)
  }

  /// Exchange an email and password for a Supabase access token, with the
  /// lifetime the provider reports so callers can renew before it lapses.
  public static func accessToken(
    email: String,
    password: String
  ) async throws -> (token: String, expiresIn: TimeInterval) {
    try await tokenWithExpiry(email: email, password: password)
  }

  /// Exchange an email and password for a Supabase access token.
  private static func token(email: String, password: String) async throws -> String {
    try await tokenWithExpiry(email: email, password: password).token
  }

  private static func tokenWithExpiry(
    email: String,
    password: String
  ) async throws -> (token: String, expiresIn: TimeInterval) {
    guard let url = URL(string: "\(supabaseUrl)/auth/v1/token?grant_type=password") else {
      throw AlcoveAuthError.unreachable
    }
    let body = try JSONSerialization.data(withJSONObject: [
      "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
      "password": password,
    ])
    let (data, http) = try await post(url, body: body, headers: [
      "apikey": supabaseAnonKey,
      "content-type": "application/json",
    ])
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    guard http.statusCode == 200, let access = json?["access_token"] as? String else {
      let msg = (json?["error_description"] as? String)
        ?? (json?["msg"] as? String)
        ?? "Sign in failed"
      throw AlcoveAuthError.badCredentials(msg)
    }
    // Supabase reports this in seconds; an hour is its usual default.
    let ttl = (json?["expires_in"] as? Double) ?? 3600
    return (access, ttl)
  }

  /// Push this password to the music server so the Subsonic calls below
  /// authenticate. Harmless when it is already in step, and deliberately not
  /// fatal: someone signing in to browse should not be blocked by it.
  private static func syncPassword(token: String, password: String) async {
    guard let url = URL(string: "\(host)/request/api/sync-password"),
          let body = try? JSONSerialization.data(withJSONObject: ["password": password])
    else { return }
    _ = try? await post(url, body: body, headers: [
      "authorization": "Bearer \(token)",
      "content-type": "application/json",
    ])
  }

  /// The Subsonic username for this identity.
  private static func subsonicUser(token: String) async throws -> String {
    guard let url = URL(string: "\(host)/api/me") else { throw AlcoveAuthError.unreachable }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw AlcoveAuthError.unreachable }
    if http.statusCode == 401 { throw AlcoveAuthError.notLicensed }
    if http.statusCode == 404 { throw AlcoveAuthError.noAccount }
    guard http.statusCode == 200,
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let user = json["subsonicUser"] as? String, !user.isEmpty
    else { throw AlcoveAuthError.noAccount }
    return user
  }

  /// Sign in and produce credentials the existing backend code can use
  /// unchanged. Everything downstream of this stays stock Amperfy.
  public static func signIn(email: String, password: String) async throws -> LoginCredentials {
    let minted = try await tokenWithExpiry(email: email, password: password)
    let access = minted.token
    await syncPassword(token: access, password: password)
    let user = try await subsonicUser(token: access)

    // The request and manage tabs call Alcove's own API with this identity.
    // Seeding it here means they work immediately after signing in, without
    // a second round trip to the identity provider.
    await AlcoveSession.shared.configure(email: email, password: password)

    var creds = LoginCredentials()
    creds.serverUrl = host
    creds.activeBackendServerUrl = host
    creds.username = user
    creds.password = password
    creds.backendApi = .subsonic
    return creds
  }
}
