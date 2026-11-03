//
//  WebPlayerVC.swift
//  Amperfy
//
//  Alcove: the web player tab (Settings > Player Interface > Web), Dean 2026-11-03. Shows alcove.netsuite.tech/listen,
//  the iPod or the standard player as the person chose on the server; each page has its own switch to the other.
//  - Signed in as the app account: the app's own token becomes the page's session (AlcoveWebSession.appSession), minted
//    each time the tab loads and again when the page asks to sign in.
//  - Played by the app's player: the page finds window.AlcovePlayer (AlcovePlayerBridge, the Android app's contract)
//    and drives AmperfyKit's player through it, so the lock screen, background play and CarPlay work.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import UIKit
import WebKit

// MARK: - WebPlayerVC

final class WebPlayerVC: UIViewController, WKNavigationDelegate, WKUIDelegate,
  WKScriptMessageHandler {
  /// nil only for the DEBUG preview (no account signed in)
  private let account: Account?
  private var web: WKWebView!
  private let message = UILabel()
  private var signingIn = false
  private var stateTimer: Timer?
  private var lastState = ""
  /// Art ids the page sent with its songs, for the snapshot it reads back (the page builds the art URL from them).
  private var arts: [String: String] = [:]

  /// DEBUG builds can point the player at the Alcove fixture server: `-AlcoveWebPlayerURL http://127.0.0.1:8792/listen`.
  private var previewURL: URL? {
    #if DEBUG
      if let s = UserDefaults.standard
        .string(forKey: "AlcoveWebPlayerURL") { return URL(string: s) }
    #endif
    return nil
  }

  private var startURL: URL { previewURL ?? AlcoveWebSession.playerURL }

  init(account: Account?) {
    self.account = account
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()
    config.allowsInlineMediaPlayback = true
    config.allowsAirPlayForMediaPlayback = true
    config.userContentController.addUserScript(WKUserScript(
      source: AlcovePlayerBridge.shimSource,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true
    ))
    config.userContentController.add(WeakScriptHandler(self), name: AlcovePlayerBridge.handlerName)
    web = WKWebView(frame: view.bounds, configuration: config)
    web.navigationDelegate = self
    web.uiDelegate = self
    web.isOpaque = false
    web.backgroundColor = .black
    web.scrollView.contentInsetAdjustmentBehavior = .never
    view.addSubview(web)

    message.numberOfLines = 0
    message.textAlignment = .center
    message.textColor = .secondaryLabel
    message.translatesAutoresizingMaskIntoConstraints = false
    message.isHidden = true
    message.isUserInteractionEnabled = true
    message.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retry)))
    view.addSubview(message)
    NSLayoutConstraint.activate([
      message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])

    // The page reads the player's state from the last snapshot pushed here, twice a second, as on Android.
    stateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
      // Stops itself once this controller is gone
      guard let self else { return timer.invalidate() }
      MainActor.assumeIsolated { self.pushState() }
    }
    signInAndLoad()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if !message.isHidden { retry() }
  }

  /// After a failure (shown as a message, which a tap also retries): sign in and load again.
  @objc
  private func retry() {
    message.isHidden = true
    signInAndLoad()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // The page draws its own bars; keep it clear of the status bar and the floating tab bar.
    web.frame = view.bounds.inset(by: UIEdgeInsets(
      top: view.safeAreaInsets.top,
      left: 0,
      bottom: view.safeAreaInsets.bottom,
      right: 0
    ))
  }

  // MARK: Sign-in: the app account's session as the page's cookie

  private func signInAndLoad() {
    if previewURL != nil {
      web.load(URLRequest(url: startURL))
      return
    }
    guard !signingIn else { return }
    signingIn = true
    Task { @MainActor in
      defer { self.signingIn = false }
      do {
        guard let account else { return show("Sign in to the app first.") }
        let alcove = AlcoveSessionStore.shared.session(for: account.info.ident)
        var sid: String
        do {
          sid = try await AlcoveWebSession.appSession(token: alcove.validToken())
        } catch AlcoveAuthError.badCredentials {
          // An expired app token: get a fresh one once
          alcove.invalidate()
          sid = try await AlcoveWebSession.appSession(token: alcove.validToken())
        }
        guard let cookie = AlcoveWebSession.cookie(session: sid) else {
          return show("Could not sign the player in. Tap to try again.")
        }
        let store = web.configuration.websiteDataStore.httpCookieStore
        await AlcoveWebSession.clearCookies(in: store)
        await store.setCookie(cookie)
        message.isHidden = true
        web.load(URLRequest(url: startURL))
      } catch {
        show("\(error.localizedDescription) Tap to try again.")
      }
    }
  }

  // MARK: Navigation: Alcove's pages only; its sign-in link signs it in as the app account

  func webView(
    _ webView: WKWebView,
    decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> ()
  ) {
    guard let url = action.request.url else { return decisionHandler(.cancel) }
    // Frames inside the page, and its own blob:, data: and about: URLs, are the page's business
    if action.targetFrame?.isMainFrame == false || ["blob", "data", "about"]
      .contains(url.scheme ?? "") {
      return decisionHandler(.allow)
    }
    if AlcoveWebSession.isSignIn(url) {
      decisionHandler(.cancel)
      signInAndLoad()
      return
    }
    if let preview = previewURL, url.host == preview.host { return decisionHandler(.allow) }
    if AlcoveWebSession.isAlcove(url) { return decisionHandler(.allow) }
    decisionHandler(.cancel)
    UIApplication.shared.open(url)
  }

  /// A link meant for a new window (target=_blank) opens in the browser, so the player page stays.
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for action: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  )
    -> WKWebView? {
    if let url = action.request.url { UIApplication.shared.open(url) }
    return nil
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    let e = error as NSError
    // A load replaced by another (-999) or stopped by the policy above (WebKit 102) is not a failure
    if e.domain == NSURLErrorDomain, e.code == NSURLErrorCancelled { return }
    if e.domain == "WebKitErrorDomain", e.code == 102 { return }
    show("Alcove is not reachable. Tap to try again.")
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    message.isHidden = true
    lastState = ""
  }

  /// iOS can end the page's process while the app is in the background: load it again.
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    webView.load(URLRequest(url: startURL))
  }

  // MARK: window.AlcovePlayer: the page drives the app's player

  func userContentController(
    _ controller: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    guard message.name == AlcovePlayerBridge.handlerName, let body = message.body as? [String: Any],
          let op = body["op"] as? String else { return }
    let player = appDelegate.player
    switch op {
    case "enqueue", "load":
      guard let json = body["json"] as? String,
            let (items, index) = AlcovePlayerBridge.parseQueue(json) else { return }
      for item in items where !item.art.isEmpty { arts[item.id] = item.art }
      let next = body["next"] as? Bool ?? false
      Task { @MainActor in
        let songs = await self.songs(for: items)
        guard !songs.isEmpty
        else {
          return self.show("These songs are not in the app's library yet. Tap to try again.")
        }
        if op == "load" {
          // The index of the song asked for, among the ones found
          let wanted = items[index].id
          let start = songs.firstIndex(where: { $0.id == wanted }) ?? 0
          player.play(context: PlayContext(name: "Alcove", index: start, playables: songs))
        } else if next {
          player.insertUserQueue(playables: songs)
        } else {
          player.appendUserQueue(playables: songs)
        }
        self.pushState()
      }
    case "toggle": player.togglePlayPause()
    case "pause": player.pause()
    case "next": player.playNext()
    case "previous": player.playPreviousOrReplay()
    case "seek": player.seek(toSecond: (body["value"] as? NSNumber)?.doubleValue ?? 0)
    case "volume": appDelegate.player.volume = (body["value"] as? NSNumber)?.floatValue ?? player
      .volume
    case "repeat": player
      .setRepeatMode(AlcovePlayerBridge.repeatMode(body["mode"] as? String ?? "off"))
    case "shuffle":
      if (body["on"] as? Bool ?? false) != player.isShuffle { player.toggleShuffle() }
    case "stop": player.stop()
    case "reauth": signInAndLoad()
    default: break
    }
  }

  /// The songs for the page's ids, from the app's library; the ones it lacks are looked up on the server by title
  /// (a search syncs them in), then read again. Ids it cannot find are left out.
  private func songs(for items: [AlcovePlayerBridge.Item]) async -> [Song] {
    guard let account else { return [] }
    let library = appDelegate.storage.main.library
    let missing = items.filter { library.getSong(for: account, id: $0.id) == nil }
    if !missing.isEmpty, !appDelegate.storage.settings.user.isOfflineMode {
      let syncer = appDelegate.getMeta(account.info).librarySyncer
      for title in Set(missing.prefix(20).map(\.title)) where !title.isEmpty {
        try? await syncer.searchSongs(searchText: title)
      }
    }
    return items.compactMap { library.getSong(for: account, id: $0.id) }
  }

  private func pushState() {
    guard isViewLoaded, web != nil else { return }
    let player = appDelegate.player
    let prev = player.getAllPrevQueueItems()
    let next = player.getAllNextQueueItems()
    let current = player.currentlyPlaying
    let ids = prev.map(\.id) + (current.map { [$0.id] } ?? []) + next.map(\.id)
    let item = current.map { p in
      let song = p as? Song
      return AlcovePlayerBridge.Item(
        id: p.id,
        title: p.title,
        artist: song?.artist?.name ?? p.creatorName,
        album: song?.album?.name ?? "",
        art: arts[p.id] ?? "",
        seconds: p.duration
      )
    }
    let state = AlcovePlayerBridge.stateJSON(
      playing: player.isPlaying,
      time: player.elapsedTime,
      duration: player.duration,
      ids: ids,
      index: prev.count,
      current: item
    )
    guard state != lastState else { return }
    lastState = state
    web.evaluateJavaScript(AlcovePlayerBridge.pushScript(state: state))
  }

  private func show(_ text: String) {
    message.text = text
    message.isHidden = false
  }
}

// MARK: - WeakScriptHandler

/// WKUserContentController keeps its handlers strongly; this keeps the player controller from being held by its own page.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?
  init(_ target: WKScriptMessageHandler) { self.target = target }
  func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(c, didReceive: message)
  }
}
