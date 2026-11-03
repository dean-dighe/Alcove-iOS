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

Dean, 2026-11-03: the web player on every platform. *Native* (the default) is Amperfy's own screens. *Web* adds a
Player tab, first in the bar, with `alcove.netsuite.tech/listen` in a `WKWebView` (`Amperfy/Screens/Alcove/WebPlayerVC.swift`):
the iPod or the standard player, chosen inside the page and kept per person on the server (`/api/v1/prefs`), so the
choice follows the person to the web and the Android app.

- **Sign-in** (`AmperfyKit/Api/AlcoveWebSession.swift`), the way the Android app's WebView gets its session: when the
  page links to `/auth/login` (signed out, or the session expired), the app opens Alcove's app sign-in in the system
  sheet (`ASWebAuthenticationSession`, `/auth/login?client=ios&challenge=<S256>`, Google), takes the one-time code from
  `alcove://auth-callback`, exchanges it with its verifier at `POST /auth/exchange`, and sets the session as the page's
  `__Host-alcove_sid` cookie (30 days, kept in the web view's own store). Needs the Worker to accept `client=ios`
  (Alcove PR 1). Google refuses sign-in inside a web view, which is why it is the sheet.
- **Playback** is the page's own audio element: it plays while the app is open. The lock screen, background play and
  CarPlay stay with the native player.
- **A native bridge** would close that gap. The page already speaks to one on Android: `window.AlcovePlayer` with
  `load(json)` (`{index, queue: [{id, title, artist, album, art, seconds}]}`), `enqueue(json, next)`, `toggle()`,
  `pause()`, `next()`, `previous()`, `seek(seconds)`, `setVolume(v)`, `setRepeat("off"|"one"|"all")`, `setShuffle(on)`,
  `stop()`, `state()` (synchronous: `{playing, loading, time, duration, index, ids, current}` as JSON) and `reauth()`.
  On iOS: a `WKUserScript` at document start defines `window.AlcovePlayer` over a `WKScriptMessageHandler` for the
  calls, and the app pushes the player's snapshot into the page twice a second for `state()`; the ids are the Subsonic
  ids AmperfyKit already plays.
- DEBUG builds take `-AlcoveWebPlayerURL <url>` to show Alcove's fixture server (`worker/dev/fixture-server.mjs`).

## Build and install

Xcode 26 with an Apple account for team WCF4XQ2RNJ signed in (Xcode > Settings > Accounts), so that
automatic signing can make the development profile. Then, with the iPhone unlocked:

    xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -configuration Release \
      -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build
    xcrun devicectl device install app --device "Dean i17" build/Build/Products/Release-iphoneos/Amperfy.app

To check that it compiles without signing, add `CODE_SIGNING_ALLOWED=NO`.
