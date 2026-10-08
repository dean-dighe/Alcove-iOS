//
//  AlcoveShares.swift
//  AmperfyKit
//
//  A playlist shared to you is a copy you own, named "<owner>'s <name>" by the
//  server. The app shows it under its own name with a "Shared by <owner>" pill
//  (Dean, 2026-10-08), as the Android app does.
//
//  Licensed under GPL-3.0, as the rest of this project is.
//

import Foundation

public enum AlcoveShares {
  /// (owner, name) for a shared playlist's name, or nil for one of your own.
  public static func sharedBy(_ playlistName: String) -> (owner: String, name: String)? {
    guard let regex = try? NSRegularExpression(pattern: "^([a-z0-9._-]+)'s (.+)$"),
          let m = regex.firstMatch(
            in: playlistName,
            range: NSRange(playlistName.startIndex..., in: playlistName)
          ),
          let owner = Range(m.range(at: 1), in: playlistName),
          let name = Range(m.range(at: 2), in: playlistName)
    else { return nil }
    return (String(playlistName[owner]), String(playlistName[name]))
  }
}
