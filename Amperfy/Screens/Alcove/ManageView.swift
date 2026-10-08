//
//  ManageView.swift
//  Amperfy
//
//  Fix metadata and organise playlists. Mirrors the /manage page: search the
//  library, correct a title, artist or album, and move tracks in and out of
//  your own playlists. Delete songs (the server removes them too), and add
//  music from YouTube straight into a playlist (Dean, 2026-10-08).
//
//  Licensed under GPL-3.0, as the rest of this project is.
//

import AmperfyKit
import SwiftUI

@MainActor
final class ManageModel: ObservableObject {
  @Published var query = ""
  @Published var tracks: [AlcoveTrack] = []
  @Published var playlists: [String] = []
  @Published var total = 0
  @Published var loading = false
  @Published var notice = ""
  @Published var noticeGood = true
  @Published var editing: AlcoveTrack?
  @Published var selected: Set<String> = []
  @Published var confirmingDelete = false
  /// The playlist the Add from YouTube sheet is filling, when it is open.
  @Published var youtubeTarget: YouTubeTarget?

  var selecting: Bool { !selected.isEmpty }

  private let accountId: String
  var accountIdForSheets: String { accountId }

  init(accountId: String) {
    self.accountId = accountId
  }

  func load() async {
    loading = true
    defer { loading = false }
    do {
      let page = try await AlcoveAPI.library(
        matching: query.trimmingCharacters(in: .whitespacesAndNewlines),
        accountId: accountId
      )
      tracks = page.tracks
      playlists = page.playlists
      total = page.total
    } catch {
      show(error.localizedDescription, good: false)
    }
  }

  func save(_ track: AlcoveTrack, title: String, artist: String, album: String) async {
    do {
      try await AlcoveAPI.edit(
        id: track.id,
        title: title,
        artist: artist,
        album: album,
        accountId: accountId
      )
      show("Saved. The Music tab catches up shortly.", good: true)
      editing = nil
      await load()
    } catch {
      show(error.localizedDescription, good: false)
    }
  }

  func membership(playlist: String, add: Bool) async {
    let rels = tracks.filter { selected.contains($0.id) }.map(\.rel)
    guard !rels.isEmpty else { return }
    do {
      try await AlcoveAPI.setMembership(
        rels: rels,
        addTo: add ? playlist : nil,
        removeFrom: add ? nil : playlist,
        accountId: accountId
      )
      show(
        "\(rels.count) track\(rels.count == 1 ? "" : "s") "
          + (add ? "added to " : "removed from ") + playlist,
        good: true
      )
      selected.removeAll()
      await load()
    } catch {
      show(error.localizedDescription, good: false)
    }
  }

  /// Delete the selected songs from your library, and from the server.
  func deleteSelected() async {
    let rels = tracks.filter { selected.contains($0.id) }.map(\.rel).filter { !$0.isEmpty }
    guard !rels.isEmpty else { return }
    do {
      let done = try await AlcoveAPI.deleteTracks(rels: rels, accountId: accountId)
      var text = "Deleted \(done.deleted.count) song\(done.deleted.count == 1 ? "" : "s")."
      if !done.kept.isEmpty {
        text += " \(done.kept.count) kept on the server: someone else's library still has \(done.kept.count == 1 ? "it" : "them")."
      }
      show(text, good: true)
      selected.removeAll()
      await load()
    } catch {
      show(error.localizedDescription, good: false)
    }
  }

  func toggle(_ track: AlcoveTrack) {
    if selected.contains(track.id) {
      selected.remove(track.id)
    } else {
      selected.insert(track.id)
    }
  }

  private func show(_ text: String, good: Bool) {
    notice = text
    noticeGood = good
  }
}

struct ManageView: View {
  @StateObject private var model: ManageModel

  init(accountId: String) {
    _model = StateObject(wrappedValue: ManageModel(accountId: accountId))
  }

  var body: some View {
    ZStack {
      Alcove.bg.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: Alcove.gap) {
          AlcoveSearchField(placeholder: "Search your library", text: $model.query) {
            Task { await model.load() }
          }

          AlcoveNotice(text: model.notice, good: model.noticeGood)

          if !model.playlists.isEmpty {
            Menu {
              Section("Add from YouTube into") {
                ForEach(model.playlists, id: \.self) { name in
                  Button(name) { model.youtubeTarget = YouTubeTarget(playlist: name) }
                }
              }
            } label: {
              Label("Add from YouTube", systemImage: "plus.rectangle.on.rectangle")
                .font(Alcove.label)
                .foregroundStyle(Alcove.accent)
            }
          }

          if model.selecting {
            PlaylistBar(playlists: model.playlists, count: model.selected.count) { name, add in
              Task { await model.membership(playlist: name, add: add) }
            } clear: {
              model.selected.removeAll()
            } delete: {
              model.confirmingDelete = true
            }
          }

          if model.loading {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text("Loading").font(Alcove.label).foregroundStyle(Alcove.dim)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
          } else if model.tracks.isEmpty {
            AlcoveEmpty(
              icon: "music.note.list",
              title: "Nothing here",
              detail: model.query.isEmpty
                ? "Your library is empty, or it is still being indexed."
                : "No track matches that search."
            )
          } else {
            Text("\(model.total) track\(model.total == 1 ? "" : "s")")
              .font(Alcove.caption)
              .foregroundStyle(Alcove.dim)
            ForEach(model.tracks) { t in
              TrackRow(
                track: t,
                selected: model.selected.contains(t.id),
                selecting: model.selecting
              ) {
                model.toggle(t)
              } edit: {
                model.editing = t
              }
            }
          }
        }
        .padding(Alcove.inset)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .task { await model.load() }
    .confirmationDialog(
      "Delete \(model.selected.count) song\(model.selected.count == 1 ? "" : "s") from your library? They are removed from the server too.",
      isPresented: $model.confirmingDelete,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) { Task { await model.deleteSelected() } }
    }
    .sheet(item: $model.youtubeTarget) { target in
      YouTubeSheet(playlist: target.playlist, accountId: model.accountIdForSheets)
    }
    .sheet(item: $model.editing) { track in
      EditSheet(track: track) { title, artist, album in
        Task { await model.save(track, title: title, artist: artist, album: album) }
      } cancel: {
        model.editing = nil
      }
    }
  }
}

private struct TrackRow: View {
  let track: AlcoveTrack
  let selected: Bool
  let selecting: Bool
  let toggle: () -> ()
  let edit: () -> ()

  var body: some View {
    AlcoveCard {
      HStack(spacing: Alcove.gap) {
        Button(action: toggle) {
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(selected ? Alcove.accent : Alcove.line)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "Deselect" : "Select")

        VStack(alignment: .leading, spacing: 2) {
          Text(track.title.isEmpty ? "Untitled" : track.title)
            .font(Alcove.body)
            .foregroundStyle(Alcove.fg)
            .lineLimit(1)
          Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(Alcove.caption)
            .foregroundStyle(Alcove.dim)
            .lineLimit(1)
          if !track.playlists.isEmpty {
            Text(track.playlists.joined(separator: ", "))
              .font(Alcove.caption)
              .foregroundStyle(Alcove.accent)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)

        Button(action: edit) {
          Image(systemName: "pencil").font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Alcove.dim)
        .accessibilityLabel("Edit details")
      }
    }
  }
}

private struct PlaylistBar: View {
  let playlists: [String]
  let count: Int
  let apply: (String, Bool) -> ()
  let clear: () -> ()
  let delete: () -> ()

  var body: some View {
    AlcoveCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("\(count) selected").font(Alcove.label).foregroundStyle(Alcove.fg)
          Spacer()
          Button(role: .destructive, action: delete) {
            Label("Delete", systemImage: "trash")
          }
          .font(Alcove.label)
          .foregroundStyle(Alcove.bad)
          .buttonStyle(.plain)
          .padding(.trailing, 8)
          Button("Clear", action: clear)
            .font(Alcove.label)
            .foregroundStyle(Alcove.accent)
            .buttonStyle(.plain)
        }
        if playlists.isEmpty {
          Text("You have no playlists yet.")
            .font(Alcove.caption)
            .foregroundStyle(Alcove.dim)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(playlists, id: \.self) { name in
                Menu {
                  Button("Add to \(name)") { apply(name, true) }
                  Button("Remove from \(name)", role: .destructive) { apply(name, false) }
                } label: {
                  Text(name)
                    .font(Alcove.caption)
                    .foregroundStyle(Alcove.fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Alcove.bg)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Alcove.line, lineWidth: 1))
                }
              }
            }
          }
        }
      }
    }
  }
}

private struct EditSheet: View {
  let track: AlcoveTrack
  let save: (String, String, String) -> ()
  let cancel: () -> ()

  @State private var title: String
  @State private var artist: String
  @State private var album: String

  init(
    track: AlcoveTrack,
    save: @escaping (String, String, String) -> (),
    cancel: @escaping () -> ()
  ) {
    self.track = track
    self.save = save
    self.cancel = cancel
    _title = State(initialValue: track.title)
    _artist = State(initialValue: track.artist)
    _album = State(initialValue: track.album)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Alcove.bg.ignoresSafeArea()
        VStack(spacing: Alcove.gap) {
          field("Title", $title)
          field("Artist", $artist)
          field("Album", $album)
          Spacer()
        }
        .padding(Alcove.inset)
      }
      .navigationTitle("Edit track")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: cancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            save(
              title.trimmingCharacters(in: .whitespacesAndNewlines),
              artist.trimmingCharacters(in: .whitespacesAndNewlines),
              album.trimmingCharacters(in: .whitespacesAndNewlines)
            )
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func field(_ label: String, _ value: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(Alcove.caption).foregroundStyle(Alcove.dim)
      TextField("", text: value)
        .font(Alcove.body)
        .foregroundStyle(Alcove.fg)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Alcove.surface)
        .clipShape(RoundedRectangle(cornerRadius: Alcove.radius, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Alcove.radius, style: .continuous)
            .stroke(Alcove.line, lineWidth: 1)
        )
    }
  }
}

struct YouTubeTarget: Identifiable {
  let playlist: String
  var id: String { playlist }
}

/// Search YouTube and add a result straight into one playlist. It is queued for
/// import the normal way; the import puts it in this playlist.
@MainActor
private final class YouTubeModel: ObservableObject {
  @Published var query = ""
  @Published var results: [AlcoveSearchResult] = []
  @Published var searching = false
  @Published var queued: Set<String> = []
  @Published var notice = ""
  @Published var noticeGood = true

  let playlist: String
  private let accountId: String

  init(playlist: String, accountId: String) {
    self.playlist = playlist
    self.accountId = accountId
  }

  func search() async {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard q.count >= 2 else { return }
    searching = true
    defer { searching = false }
    do {
      results = try await AlcoveAPI.search(q, accountId: accountId)
      if results.isEmpty { show("Nothing found for that.", good: false) } else { notice = "" }
    } catch {
      show(error.localizedDescription, good: false)
    }
  }

  func add(_ r: AlcoveSearchResult) async {
    do {
      let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
      try await AlcoveAPI.queue(query: q.isEmpty ? r.title : q, videoId: r.id, playlist: playlist, accountId: accountId)
      queued.insert(r.id)
      show(r.owned ? "Added to \(playlist)." : "Queued into \(playlist). It usually lands within a minute.", good: true)
    } catch {
      show(error.localizedDescription, good: false)
    }
  }

  private func show(_ text: String, good: Bool) {
    notice = text
    noticeGood = good
  }
}

private struct YouTubeSheet: View {
  @StateObject private var model: YouTubeModel
  @Environment(\.dismiss) private var dismiss

  init(playlist: String, accountId: String) {
    _model = StateObject(wrappedValue: YouTubeModel(playlist: playlist, accountId: accountId))
  }

  var body: some View {
    NavigationStack {
      ZStack {
        Alcove.bg.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: Alcove.gap) {
            AlcoveSearchField(placeholder: "Artist and song, or a YouTube link", text: $model.query) {
              Task { await model.search() }
            }
            AlcoveNotice(text: model.notice, good: model.noticeGood)
            if model.searching {
              ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            ForEach(model.results) { r in
              AlcoveCard {
                HStack(spacing: Alcove.gap) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(r.title).font(Alcove.body).foregroundStyle(Alcove.fg).lineLimit(2)
                    Text([r.uploader, r.durationText].filter { !$0.isEmpty }.joined(separator: " · ")
                      + (r.owned ? " · already in the library" : ""))
                      .font(Alcove.caption)
                      .foregroundStyle(r.owned ? Alcove.ok : Alcove.dim)
                      .lineLimit(1)
                  }
                  Spacer(minLength: 0)
                  Button {
                    Task { await model.add(r) }
                  } label: {
                    Image(systemName: model.queued.contains(r.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                      .font(.system(size: 22))
                  }
                  .buttonStyle(.plain)
                  .foregroundStyle(model.queued.contains(r.id) ? Alcove.ok : Alcove.accent)
                  .disabled(model.queued.contains(r.id))
                  .accessibilityLabel("Add to \(model.playlist)")
                }
              }
            }
          }
          .padding(Alcove.inset)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .navigationTitle("Add to \(model.playlist)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }
}
