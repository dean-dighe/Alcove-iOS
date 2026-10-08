//
//  RequestView.swift
//  Amperfy
//
//  Ask for music the library does not have yet. Mirrors the /request page:
//  search, see what is already owned, queue the rest, and watch it arrive.
//  Every result goes straight into a playlist in one step (Dean, 2026-10-08):
//  pick it from the result's Add to menu and the import puts it there.
//
//  Licensed under GPL-3.0, as the rest of this project is.
//

import AmperfyKit
import SwiftUI

@MainActor
final class RequestModel: ObservableObject {
  @Published var query = ""
  @Published var results: [AlcoveSearchResult] = []
  @Published var mine: [AlcoveRequest] = []
  @Published var searching = false
  @Published var notice = ""
  @Published var noticeGood = true
  @Published var searched = false
  /// Ids currently being queued, so a row can show progress without freezing
  /// the whole list.
  @Published var queueing: Set<String> = []
  /// Your own playlists, for the Add to menu.
  @Published var playlists: [String] = []

  private let accountId: String

  init(accountId: String) {
    self.accountId = accountId
  }

  func search() async {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard q.count >= 2 else {
      show("Type a bit more.", good: false)
      return
    }
    searching = true
    notice = ""
    defer { searching = false }
    do {
      results = try await AlcoveAPI.search(q, accountId: accountId)
      searched = true
      if results.isEmpty { show("Nothing found for that.", good: false) }
    } catch {
      show(error.localizedDescription, good: false)
    }
  }

  /// Queue one result into `playlist` (nil: the requests playlist).
  func queue(_ r: AlcoveSearchResult, into playlist: String? = nil) async {
    queueing.insert(r.id)
    defer { queueing.remove(r.id) }
    do {
      let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
      try await AlcoveAPI.queue(
        query: q.isEmpty ? r.title : q,
        videoId: r.id,
        playlist: playlist,
        accountId: accountId
      )
      let destination = playlist ?? "Requests"
      show(
        r.owned
          ? "Added to \(destination). Already in the library, so no download needed."
          : "Queued into \(destination). It usually lands within a minute.",
        good: true
      )
      await loadMine()
    } catch {
      show(error.localizedDescription, good: false)
    }
  }

  func loadPlaylists() async {
    // A query no track matches returns the playlist names alone, keeping it small.
    if let page = try? await AlcoveAPI.library(matching: "\u{0}", accountId: accountId) {
      playlists = page.playlists
    }
  }

  func loadMine() async {
    do {
      mine = try await AlcoveAPI.myRequests(accountId: accountId)
    } catch {
      // A failure here is not worth interrupting the search flow over.
    }
  }

  private func show(_ text: String, good: Bool) {
    notice = text
    noticeGood = good
  }
}

struct RequestView: View {
  @StateObject private var model: RequestModel

  init(accountId: String) {
    _model = StateObject(wrappedValue: RequestModel(accountId: accountId))
  }

  var body: some View {
    ZStack {
      Alcove.bg.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: Alcove.gap) {
          AlcoveSearchField(
            placeholder: "Artist and song, or a YouTube link",
            text: $model.query
          ) {
            Task { await model.search() }
          }

          AlcoveNotice(text: model.notice, good: model.noticeGood)

          if model.searching {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text("Searching").font(Alcove.label).foregroundStyle(Alcove.dim)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
          } else if !model.results.isEmpty {
            ForEach(model.results) { r in
              ResultRow(
                result: r,
                busy: model.queueing.contains(r.id),
                playlists: model.playlists
              ) { playlist in
                Task { await model.queue(r, into: playlist) }
              }
            }
          } else if model.searched {
            AlcoveEmpty(
              icon: "magnifyingglass",
              title: "No matches",
              detail: "Try the artist and the song title together."
            )
          }

          if !model.mine.isEmpty {
            Text("Your requests")
              .font(Alcove.label)
              .foregroundStyle(Alcove.dim)
              .padding(.top, 8)
            ForEach(model.mine) { r in
              RequestRow(request: r)
            }
          }
        }
        .padding(Alcove.inset)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .task {
      await model.loadMine()
      await model.loadPlaylists()
    }
  }
}

private struct ResultRow: View {
  let result: AlcoveSearchResult
  let busy: Bool
  let playlists: [String]
  let onQueue: (String?) -> ()

  var body: some View {
    AlcoveCard {
      HStack(alignment: .top, spacing: Alcove.gap) {
        VStack(alignment: .leading, spacing: 4) {
          Text(result.title)
            .font(Alcove.body)
            .foregroundStyle(Alcove.fg)
            .lineLimit(2)
          HStack(spacing: 6) {
            Text(result.uploader).lineLimit(1)
            if !result.durationText.isEmpty {
              Text("·")
              Text(result.durationText)
            }
          }
          .font(Alcove.caption)
          .foregroundStyle(Alcove.dim)

          if result.owned {
            // Say what it is already filed as. Titles get tidied on import,
            // so the library name rarely matches the YouTube one.
            Text(result.ownedAs.isEmpty
              ? "Already in the library"
              : "Already in the library as \(result.ownedAs)")
              .font(Alcove.caption)
              .foregroundStyle(Alcove.ok)
              .lineLimit(2)
          }
        }

        Spacer(minLength: 0)

        Menu {
          Section("Add to") {
            Button { onQueue(nil) } label: { Label("Requests", systemImage: "tray.and.arrow.down") }
            ForEach(playlists, id: \.self) { name in
              Button { onQueue(name) } label: { Label(name, systemImage: "music.note.list") }
            }
          }
        } label: {
          if busy {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "plus.circle.fill")
              .font(.system(size: 22))
          }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Alcove.accent)
        .disabled(busy)
        .accessibilityLabel("Add to a playlist")
      }
    }
  }
}

private struct RequestRow: View {
  let request: AlcoveRequest

  private var colour: Color {
    switch request.status {
    case "done": Alcove.ok
    case "failed": Alcove.bad
    default: Alcove.dim
    }
  }

  private var symbol: String {
    switch request.status {
    case "done": "checkmark.circle.fill"
    case "failed": "exclamationmark.triangle.fill"
    default: "clock"
    }
  }

  var body: some View {
    AlcoveCard {
      HStack(spacing: Alcove.gap) {
        Image(systemName: symbol).foregroundStyle(colour)
        VStack(alignment: .leading, spacing: 2) {
          Text(request.query)
            .font(Alcove.label)
            .foregroundStyle(Alcove.fg)
            .lineLimit(1)
          if !request.playlist.isEmpty {
            Text("into \(request.playlist)")
              .font(Alcove.caption)
              .foregroundStyle(Alcove.accent)
              .lineLimit(1)
          }
          if !request.detail.isEmpty {
            Text(request.detail)
              .font(Alcove.caption)
              .foregroundStyle(Alcove.dim)
              .lineLimit(2)
          }
        }
        Spacer(minLength: 0)
        Text(request.status)
          .font(Alcove.caption)
          .foregroundStyle(colour)
      }
    }
  }
}
