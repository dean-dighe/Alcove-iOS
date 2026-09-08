//
//  ManageView.swift
//  Amperfy
//
//  Fix metadata and organise playlists. Mirrors the /manage page: search the
//  library, correct a title, artist or album, and move tracks in and out of
//  your own playlists.
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

  var selecting: Bool { !selected.isEmpty }

  private let accountId: String

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

          if model.selecting {
            PlaylistBar(playlists: model.playlists, count: model.selected.count) { name, add in
              Task { await model.membership(playlist: name, add: add) }
            } clear: {
              model.selected.removeAll()
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

  var body: some View {
    AlcoveCard {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("\(count) selected").font(Alcove.label).foregroundStyle(Alcove.fg)
          Spacer()
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
