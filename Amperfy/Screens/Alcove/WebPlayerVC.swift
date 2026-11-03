//
//  WebPlayerVC.swift
//  Amperfy
//
//  Alcove: the web player tab (Settings > Player Interface > Web), Dean 2026-11-03. Shows alcove.netsuite.tech/listen,
//  the iPod or the standard player as the person chose on the server; each page has its own switch to the other.
//  Playback is the page's own audio element, one player at a time (page or native). A native bridge like the Android app's window.AlcovePlayer (load,
//  enqueue, toggle, next, previous, seek, state, reauth) would hand playback to AmperfyKit's player for the lock
//  screen and CarPlay; see ALCOVE.md.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import AmperfyKit
import AuthenticationServices
import UIKit
import WebKit

// MARK: - WebPlayerVC

final class WebPlayerVC: UIViewController, WKNavigationDelegate, WKUIDelegate,
  WKScriptMessageHandler,
  ASWebAuthenticationPresentationContextProviding, MusicPlayable {
  private var web: WKWebView!
  private var signIn: ASWebAuthenticationSession?
  private let message = UILabel()
  /// DEBUG builds can point the player at the Alcove fixture server: `-AlcoveWebPlayerURL http://127.0.0.1:8792/listen`.
  private var startURL: URL {
    #if DEBUG
      if let s = UserDefaults.standard.string(forKey: "AlcoveWebPlayerURL"),
         let u = URL(string: s) { return u }
    #endif
    return AlcoveWebSession.playerURL
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default() // the session cookie persists with the page's own storage
    config.allowsInlineMediaPlayback = true
    config.mediaTypesRequiringUserActionForPlayback = []
    config.allowsAirPlayForMediaPlayback = true
    // One player at a time: the page says when its audio starts, and the native player pauses then (and the page's
    // audio pauses when the native player starts, didStartPlaying below).
    config.userContentController.addUserScript(WKUserScript(
      source: "document.addEventListener('play', function () { window.webkit.messageHandlers.alcovePlay.postMessage('play'); }, true);",
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true
    ))
    config.userContentController.add(WeakScriptHandler(self), name: "alcovePlay")
    web = WKWebView(frame: view.bounds, configuration: config)
    web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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
    web.load(URLRequest(url: startURL))
    appDelegate.player.addNotifier(notifier: self)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if !message.isHidden { retry() }
  }

  func userContentController(
    _ controller: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    if message.name == "alcovePlay", appDelegate.player.isPlaying { appDelegate.player.pause() }
  }

  // MARK: MusicPlayable: the native player started, so the page's audio stops

  func didStartPlaying() {
    web?
      .evaluateJavaScript(
        "document.querySelectorAll('audio, video').forEach(function (m) { m.pause(); });"
      )
  }

  func didStartPlayingFromBeginning() { didStartPlaying() }
  func didPause() {}
  func didStopPlaying() {}
  func didElapsedTimeChange() {}
  func didPlaylistChange() {}
  func didArtworkChange() {}
  func didNowPlayingInfoChange() {}
  func didShuffleChange() {}
  func didRepeatChange() {}
  func didPlaybackRateChange() {}

  /// After a failure (shown as a message, which a tap also retries): load the player again.
  @objc
  private func retry() {
    message.isHidden = true
    web.load(URLRequest(url: startURL))
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

  // MARK: Navigation: Alcove's pages only; its sign-in link becomes the system sign-in sheet

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
      // The sign-in sheet needs this tab on screen to attach to
      if view.window == nil { show("Not signed in. Tap to sign in with Google.") }
      else { startSignIn() }
      return
    }
    #if DEBUG
      if url.host == startURL.host { return decisionHandler(.allow) }
    #endif
    if AlcoveWebSession.isAlcove(url) { return decisionHandler(.allow) }
    decisionHandler(.cancel)
    UIApplication.shared.open(url)
  }

  /// A link meant for a new window (target=_blank) opens in the browser, so the player keeps playing.
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
  }

  /// iOS can end the page's process while the app is in the background: load it again.
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    webView.load(URLRequest(url: startURL))
  }

  // MARK: Sign-in

  private func startSignIn() {
    guard signIn == nil else { return }
    let verifier = AlcoveWebSession.newVerifier()
    let url = AlcoveWebSession.signInURL(challenge: AlcoveWebSession.challenge(for: verifier))
    let session = ASWebAuthenticationSession(
      url: url,
      callback: .customScheme(AlcoveWebSession.callbackScheme)
    ) {
      [weak self] callback, error in
      Task { @MainActor in
        guard let self else { return }
        self.signIn = nil
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
          return self.show("Not signed in. Tap to sign in with Google.")
        }
        guard error == nil, let callback,
              let code = AlcoveWebSession.code(fromCallback: callback) else {
          return self.show("Sign-in did not finish. Tap to try again.")
        }
        do {
          let sid = try await AlcoveWebSession.exchange(code: code, verifier: verifier)
          guard let cookie = AlcoveWebSession.cookie(session: sid) else {
            return self.show("Sign-in did not finish. Tap to try again.")
          }
          await self.web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
          self.message.isHidden = true
          self.web.load(URLRequest(url: self.startURL))
        } catch {
          self.show(error.localizedDescription)
        }
      }
    }
    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false
    signIn = session
    if !session.start() {
      signIn = nil
      show("Sign-in could not open. Tap to try again.")
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    view.window ?? ASPresentationAnchor()
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
