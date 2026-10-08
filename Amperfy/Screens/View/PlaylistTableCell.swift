//
//  PlaylistTableCell.swift
//  Amperfy
//
//  Created by Maximilian Bauer on 09.03.19.
//  Copyright (c) 2019 Maximilian Bauer. All rights reserved.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import AmperfyKit
import UIKit

class PlaylistTableCell: BasicTableCell {
  @IBOutlet
  weak var nameLabel: UILabel!
  @IBOutlet
  weak var entityImage: EntityImageView!
  @IBOutlet
  weak var infoLabel: UILabel!

  static let rowHeight: CGFloat = 70.0 + margin.bottom + margin.top

  private var playlist: Playlist?
  private var rootView: UITableViewController?

  func display(playlist: Playlist, rootView: UITableViewController?) {
    self.playlist = playlist
    self.rootView = rootView
    if let share = AlcoveShares.sharedBy(playlist.name) {
      nameLabel.attributedText = Self.sharedName(share.name, by: share.owner, font: nameLabel.font)
    } else {
      nameLabel.attributedText = nil
      nameLabel.text = playlist.name
    }
    entityImage.display(
      theme: appDelegate.storage.settings.accounts.getSetting(playlist.account?.info).read
        .themePreference,
      container: playlist
    )
    infoLabel.text = playlist.info(
      for: playlist.account?.apiType.asServerApiType,
      details: DetailInfoType(type: .short, settings: appDelegate.storage.settings)
    )
    infoLabel.textAlignment = (traitCollection.horizontalSizeClass == .regular) ? .right : .left
    accessoryType = .disclosureIndicator
    backgroundColor = .systemBackground
  }

  /// The playlist's own name followed by a "Shared by <owner>" pill.
  static func sharedName(_ name: String, by owner: String, font: UIFont) -> NSAttributedString {
    let out = NSMutableAttributedString(string: name + "  ", attributes: [.font: font])
    let pillFont = UIFont.systemFont(ofSize: max(10, font.pointSize - 5), weight: .semibold)
    let text = "Shared by \(owner)" as NSString
    let textSize = text.size(withAttributes: [.font: pillFont])
    let size = CGSize(width: ceil(textSize.width) + 14, height: ceil(textSize.height) + 6)
    let accent = UIColor(red: 0x3E / 255, green: 0xA6 / 255, blue: 0xFF / 255, alpha: 1)
    let image = UIGraphicsImageRenderer(size: size).image { _ in
      let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
      accent.withAlphaComponent(0.18).setFill()
      path.fill()
      text.draw(
        at: CGPoint(x: 7, y: 3),
        withAttributes: [.font: pillFont, .foregroundColor: accent]
      )
    }
    let attachment = NSTextAttachment()
    attachment.image = image
    attachment.bounds = CGRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
    out.append(NSAttributedString(attachment: attachment))
    return out
  }
}
