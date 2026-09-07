//
//  AlcoveTheme.swift
//  Amperfy
//
//  The Unimatrix palette, kept identical to the request and manage pages at
//  worker/public/*.html so the app and the browser look like one product.
//  Change a value here and the same value should change there.
//
//  Licensed under GPL-3.0, as the rest of this project is.
//

import SwiftUI

enum Alcove {
  // MARK: Palette

  /// Near black rather than pure black: pure black on OLED makes the seams
  /// between panels disappear entirely.
  static let bg = Color(hex: 0x0B0B0C)
  static let fg = Color(hex: 0xECECEC)
  static let dim = Color(hex: 0x8A8A90)
  static let line = Color(hex: 0x26262A)
  static let accent = Color(hex: 0x3EA6FF)
  static let ok = Color(hex: 0x4CAF7D)
  static let bad = Color(hex: 0xE0604E)

  /// Panels sit just above the background. Anything heavier reads as a modal.
  static let surface = Color(hex: 0x141416)

  // MARK: Metrics

  static let radius: CGFloat = 10
  static let gap: CGFloat = 12
  static let inset: CGFloat = 16

  // MARK: Type

  static let title = Font.system(size: 20, weight: .semibold)
  static let body = Font.system(size: 15)
  static let label = Font.system(size: 13)
  static let caption = Font.system(size: 12)
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }
}

// MARK: - Shared pieces

/// A panel: the repeated container on both tabs.
struct AlcoveCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(Alcove.inset)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Alcove.surface)
      .clipShape(RoundedRectangle(cornerRadius: Alcove.radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Alcove.radius, style: .continuous)
          .stroke(Alcove.line, lineWidth: 1)
      )
  }
}

/// A short-lived result line. Colour carries the outcome, so it also states it
/// in words for anyone who cannot separate the two.
struct AlcoveNotice: View {
  let text: String
  let good: Bool

  var body: some View {
    if !text.isEmpty {
      HStack(spacing: 8) {
        Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        Text(text)
      }
      .font(Alcove.label)
      .foregroundStyle(good ? Alcove.ok : Alcove.bad)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

struct AlcoveSearchField: View {
  let placeholder: String
  @Binding var text: String
  var onSubmit: () -> ()

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(Alcove.dim)
      TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Alcove.dim))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .onSubmit(onSubmit)
        .foregroundStyle(Alcove.fg)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(Alcove.dim)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .font(Alcove.body)
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

/// Shown when a list is empty, so the tab never looks broken.
struct AlcoveEmpty: View {
  let icon: String
  let title: String
  let detail: String

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 34, weight: .light))
        .foregroundStyle(Alcove.dim)
      Text(title).font(Alcove.body).foregroundStyle(Alcove.fg)
      Text(detail)
        .font(Alcove.label)
        .foregroundStyle(Alcove.dim)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 48)
  }
}
