//
//  WebPlayerVC.swift
//  Amperfy
//
//  Alcove: the web player tab (Settings > Player Interface > Web), Dean 2026-11-03. Shows alcove.netsuite.tech/listen,
//  the iPod or the standard player as the person chose on the server; each page has its own switch to the other.
//  Playback is the page's own audio element. A native bridge like the Android app's window.AlcovePlayer (load,
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

final class WebPlayerVC: UIViewController, WKNavigationDelegate, WKUIDelegate,
  ASWebAuthenticationPresentationContextProviding {
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
    view.addSubview(message)
    NSLayoutConstraint.activate([
      message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
    ])
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
    if AlcoveWebSession.isSignIn(url) {
      decisionHandler(.cancel)
      startSignIn()
      return
    }
    #if DEBUG
      if url.host == startURL.host { return decisionHandler(.allow) }
    #endif
    if AlcoveWebSession.isAlcove(url) || url.scheme == "about" { return decisionHandler(.allow) }
    decisionHandler(.cancel)
    UIApplication.shared.open(url)
  }

  /// A link meant for a new window (target=_blank) opens in this one if it is Alcove's.
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for action: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  )
    -> WKWebView? {
    if let url = action.request.url,
       AlcoveWebSession.isAlcove(url) { webView.load(URLRequest(url: url)) }
    return nil
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    show("Alcove is not reachable. Check your connection, then open this tab again.")
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
        guard error == nil, let callback,
              let code = AlcoveWebSession.code(fromCallback: callback) else { return }
        do {
          let sid = try await AlcoveWebSession.exchange(code: code, verifier: verifier)
          guard let cookie = AlcoveWebSession.cookie(session: sid) else { return }
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
    if !session.start() { signIn = nil }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    view.window ?? ASPresentationAnchor()
  }

  private func show(_ text: String) {
    message.text = text
    message.isHidden = false
  }
}
