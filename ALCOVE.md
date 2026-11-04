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

## Web player (Settings > Player Interface)

Dean, 2026-11-03: the web player on every platform, signed in as the app account and played by the app's player.
*Native* (the default) is Amperfy's own screens. *Web* adds a Player tab, first in the bar, with
`alcove.netsuite.tech/listen` in a `WKWebView` (`Amperfy/Screens/Alcove/WebPlayerVC.swift`): the iPod or the standard
player, chosen inside the page and kept per person on the server (`/api/v1/prefs`), so the choice follows the person
to the web and the Android app.

- **Sign-in is the app account's** (`AmperfyKit/Api/AlcoveWebSession.swift`): the app sends its own Supabase token,
  the bearer the Request and Manage tabs already use, to `POST /auth/app-session` and sets the answer as the page's
  `__Host-alcove_sid` cookie (a day). It does that each time the tab loads and when the page links to `/auth/login`,
  and signing out of the account clears it. Needs the Worker route (Alcove PR 1).
- **Playback is the app's player** (`AlcovePlayerBridge`): a script at document start gives the page
  `window.AlcovePlayer`, the contract the Android app provides, so both interfaces drive AmperfyKit's player and the
  lock screen, background play and CarPlay work. Calls (`load`, `enqueue`, `toggle`, `pause`, `next`, `previous`,
  `seek`, `setVolume`, `setRepeat`, `setShuffle`, `stop`, `reauth`) arrive as script messages; `state()` is answered
  from the snapshot the app pushes into the page twice a second. The page's ids are the Subsonic ids the app plays; a
  song the app's library does not have yet is synced in by a search for its title first.
- DEBUG builds take `-AlcoveWebPlayerURL <url>` to show Alcove's fixture server (`worker/dev/fixture-server.mjs`)
  without signing in.

## Build and install

Xcode 26 with an Apple account for team WCF4XQ2RNJ signed in (Xcode > Settings > Accounts), so that
automatic signing can make the development profile. Then, with the iPhone unlocked:

    xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -configuration Release \
      -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build
    xcrun devicectl device install app --device "Dean i17" build/Build/Products/Release-iphoneos/Amperfy.app

To check that it compiles without signing, add `CODE_SIGNING_ALLOWED=NO`.
