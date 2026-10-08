# Alcove for iOS

A fork of [Amperfy](https://github.com/BLeeEZ/amperfy) (GPL-3.0) for the Alcove music library
(github.com/dean-dighe/Alcove). Bundle id `tech.netsuite.alcove`, team WCF4XQ2RNJ. The Android app
(`android/ALCOVE.md` in Alcove) has the same features.

## What differs from Amperfy

- **One Unimatrix sign-in.** `LoginVC` takes an email and password. They become a Supabase token
  (`AmperfyKit/Api/AlcoveAuth.swift`), the music server's password is synced to it, and `/api/me`
  gives the Subsonic username. There is no server address, API selector or Add Account.
- **Stays signed in until you sign out** in Settings. A refused token never clears anything: the
  Request and Manage tabs say the password changed, and music keeps playing.
- **Request tab** (`Amperfy/Screens/Alcove/RequestView.swift`): search YouTube through Alcove. Every
  result's *Add to* menu queues it into one of your playlists, or into Requests. It is imported the
  normal way and lands in that playlist. Your requests show where each one is going.
- **Manage tab** (`ManageView.swift`):
  - search your library and edit tags;
  - add a selection to playlists, or remove it;
  - *Add from YouTube* into a playlist;
  - *Delete* songs. They leave your playlists and your library on the server; a song still in someone
    else's library is kept for them.
- **Playlists**: only yours and the ones shared with you (`SsPlaylistParserDelegate` with the owner
  filter). A shared one shows its own name and a "Shared by" pill (`AlcoveShares`,
  `PlaylistTableCell`).
- **Look**: the Alcove icon (the falcon with a Lucide music badge, `AmperfyAppIcon.icon`, from
  `branding/make-logo.py` in Alcove) and the #3EA6FF accent.

Alcove's API is the web pages' (`worker/README.md` in Alcove), with the same bearer token.

## Build and install

Xcode 26 with an Apple account for team WCF4XQ2RNJ signed in (Xcode > Settings > Accounts), so that
automatic signing can make the development profile. Then, with the iPhone unlocked:

    xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -configuration Release \
      -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build
    xcrun devicectl device install app --device "Dean i17" build/Build/Products/Release-iphoneos/Amperfy.app

To check that it compiles without signing, add `CODE_SIGNING_ALLOWED=NO`.
