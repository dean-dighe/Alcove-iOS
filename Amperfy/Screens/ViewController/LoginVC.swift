//
//  LoginVC.swift
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
import SwiftUI
import UIKit

extension String {
  var isHyperTextProtocolProvided: Bool {
    hasPrefix("https://") || hasPrefix("http://")
  }
}

extension UITextField {
  func configuteForLogin(image: UIImage) {
    clipsToBounds = true
    layer.cornerRadius = 5
    layer.borderWidth = CGFloat(0.5)
    layer.borderColor = UIColor.label.cgColor

    borderStyle = .roundedRect
    font = .systemFont(ofSize: LoginVC.fontSize)

    let imageView = UIImageView(frame: CGRect(x: 5, y: 0, width: 25, height: 25))
    imageView.contentMode = .scaleAspectFit
    imageView.image = image.withRenderingMode(.alwaysTemplate)
    imageView.tintColor = .label

    let leftContainerView = UIView(frame: CGRect(x: 0, y: 0, width: 35, height: 25))
    leftContainerView.addSubview(imageView)

    leftView = leftContainerView
    leftViewMode = .always

    backgroundColor = .clear
  }
}

// MARK: - LoginVC

class LoginVC: UIViewController {
  #if targetEnvironment(macCatalyst)
    static let fontSize: CGFloat = 14
  #else
    static let fontSize: CGFloat = 16
  #endif

  fileprivate lazy var iconView: UIImageView = {
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFit
    imageView.image = .appIconTemplate
    imageView.tintColor = appDelegate.storage.settings.accounts.getSetting(nil).read.themePreference
      .asColor
    return imageView
  }()

  fileprivate lazy var brandLabel: UILabel = {
    let label = UILabel()
    label.text = "Alcove"
    label.font = .systemFont(ofSize: 50, weight: .bold)
    label.textColor = .tintColor
    label.tintColor = appDelegate.storage.settings.accounts.getSetting(nil).read.themePreference
      .asColor
    return label
  }()

  fileprivate lazy var emailTF: UITextField = {
    let textField = UITextField()
    textField.configuteForLogin(image: .userPerson)
    textField.placeholder = "Email"
    textField.textContentType = .emailAddress
    textField.keyboardType = .emailAddress
    textField.autocorrectionType = .no
    textField.autocapitalizationType = .none
    textField.addTarget(
      self,
      action: #selector(Self.emailActionPressed),
      for: .primaryActionTriggered
    )
    return textField
  }()

  @IBAction
  func emailActionPressed() {
    emailTF.resignFirstResponder()
    login()
  }

  fileprivate lazy var passwordTF: UITextField = {
    let textField = UITextField()
    textField.configuteForLogin(image: .password)
    textField.placeholder = "Password"
    textField.textContentType = .password
    textField.keyboardType = .default
    textField.isSecureTextEntry = true
    textField.autocorrectionType = .no
    textField.autocapitalizationType = .none
    textField.addTarget(
      self,
      action: #selector(Self.passwordActionPressed),
      for: .primaryActionTriggered
    )
    return textField
  }()

  @IBAction
  func passwordActionPressed() {
    passwordTF.resignFirstResponder()
    login()
  }

  fileprivate lazy var loginButton: UIButton = {
    var config = UIButton.Configuration.prominentGlass()
    config.image = .login
    config.imagePadding = 20.0
    let button = UIButton(configuration: config)
    button.setTitle("Login", for: .normal)
    button.accessibilityLabel = "Login"
    button.addTarget(self, action: #selector(Self.loginPressed), for: .touchUpInside)
    button.preferredBehavioralStyle = .pad
    return button
  }()

  // Close button shown when presented as a sheet/modal
  fileprivate lazy var closeButton: UIButton = {
    var config = UIButton.Configuration.prominentGlass()
    config.image = .xmark
    config.imagePadding = 20.0
    let button = UIButton(configuration: config)
    button.accessibilityLabel = "Close"
    button.addTarget(self, action: #selector(Self.closePressed), for: .touchUpInside)
    button.preferredBehavioralStyle = .pad
    button.isHidden = true
    return button
  }()

  @IBAction
  func closePressed() {
    // Dismiss when presented modally (e.g., as a sheet)
    if presentingViewController != nil || navigationController?.presentingViewController != nil {
      dismiss(animated: true)
    }
  }

  @IBAction
  func loginPressed() {
    emailTF.resignFirstResponder()
    passwordTF.resignFirstResponder()
    login()
  }

  /// Email and password, and nothing else.
  ///
  /// Upstream asks for a server URL, a username, a password, an API flavour
  /// and optional HTTP headers, because it talks to whatever server you point
  /// it at. This build talks to one server, over Subsonic, and identity comes
  /// from Unimatrix, so all of that is derived rather than typed and none of
  /// upstream's fields for it exist here any more.
  public lazy var formView: UIView = {
    self.emailTF.translatesAutoresizingMaskIntoConstraints = false
    self.passwordTF.translatesAutoresizingMaskIntoConstraints = false

    let view = UIView()
    view.addSubview(emailTF)
    view.addSubview(passwordTF)

    let padding: CGFloat = 0
    let elementHeight: CGFloat = 40
    let spaceInBetween: CGFloat = 15

    NSLayoutConstraint.activate([
      emailTF.safeAreaLayoutGuide.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor,
        constant: padding
      ),
      emailTF.safeAreaLayoutGuide.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor,
        constant: padding
      ),
      emailTF.safeAreaLayoutGuide.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -padding
      ),
      emailTF.heightAnchor.constraint(equalToConstant: elementHeight),

      passwordTF.safeAreaLayoutGuide.topAnchor.constraint(
        equalTo: emailTF.bottomAnchor,
        constant: spaceInBetween
      ),
      passwordTF.safeAreaLayoutGuide.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor,
        constant: padding
      ),
      passwordTF.safeAreaLayoutGuide.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -padding
      ),
      passwordTF.heightAnchor.constraint(equalToConstant: elementHeight),

      view.heightAnchor
        .constraint(equalToConstant: (2 * elementHeight) + spaceInBetween + (2 * padding)),
    ])

    return view
  }()

  var mainContainerPaddingLeadingConstraint: NSLayoutConstraint?
  var mainContainerPaddingTrailingConstraint: NSLayoutConstraint?
  var mainContainerPaddingTopConstraint: NSLayoutConstraint?
  var mainContainerPaddingBottomConstraint: NSLayoutConstraint?
  var formLeadingConstraing: NSLayoutConstraint?
  var formTrailingConstraing: NSLayoutConstraint?
  var formWitdhConstraing: NSLayoutConstraint?

  public lazy var mainContainerView: UIView = {
    self.formView.translatesAutoresizingMaskIntoConstraints = false

    let view = UIView()
    view.addSubview(formView)

    let outerInset: CGFloat = 25

    mainContainerPaddingLeadingConstraint = formView.safeAreaLayoutGuide.leadingAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.leadingAnchor,
      constant: outerInset
    )
    mainContainerPaddingTrailingConstraint = formView.safeAreaLayoutGuide.trailingAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.trailingAnchor,
      constant: -outerInset
    )
    mainContainerPaddingTopConstraint = formView.safeAreaLayoutGuide.topAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.topAnchor,
      constant: outerInset
    )
    mainContainerPaddingBottomConstraint = formView.safeAreaLayoutGuide.bottomAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.bottomAnchor,
      constant: -outerInset
    )

    NSLayoutConstraint.activate([
      mainContainerPaddingLeadingConstraint!,
      mainContainerPaddingTrailingConstraint!,
      mainContainerPaddingTopConstraint!,
      mainContainerPaddingBottomConstraint!,
    ])

    return view
  }()

  public lazy var formGlassContainer: UIVisualEffectView = {
    let container = UIVisualEffectView()
    let glassEffect = UIGlassEffect(style: .regular)
    glassEffect.isInteractive = false
    glassEffect.tintColor = appDelegate.storage.settings.accounts.getSetting(nil).read
      .themePreference.asColor
      .withAlphaComponent(0.1)
    container.effect = glassEffect
    container.cornerConfiguration = .corners(radius: 20)
    mainContainerView.translatesAutoresizingMaskIntoConstraints = false
    container.contentView.addSubview(mainContainerView)

    NSLayoutConstraint.activate([
      container.safeAreaLayoutGuide.topAnchor
        .constraint(equalTo: mainContainerView.safeAreaLayoutGuide.topAnchor),
      container.safeAreaLayoutGuide.leadingAnchor
        .constraint(equalTo: mainContainerView.safeAreaLayoutGuide.leadingAnchor),
      container.safeAreaLayoutGuide.trailingAnchor
        .constraint(equalTo: mainContainerView.safeAreaLayoutGuide.trailingAnchor),
      container.safeAreaLayoutGuide.bottomAnchor
        .constraint(equalTo: mainContainerView.safeAreaLayoutGuide.bottomAnchor),
    ])

    return container
  }()

  public lazy var loginGlassContainer: UIView = {
    loginButton
  }()

  /// Key under which the last email is remembered, so a returning user only
  /// types a password. The password itself is never stored here.
  static let lastEmailKey = "alcove.lastEmail"

  func login() {
    guard let email = emailTF.text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !email.isEmpty else {
      showErrorMsg(message: "No email given!")
      return
    }
    guard let password = passwordTF.text, !password.isEmpty else {
      showErrorMsg(message: "No password given!")
      return
    }

    Task { @MainActor in
      // Unimatrix decides who this is, and hands back the server, the Subsonic
      // username and the password to use. Everything past this point is stock
      // Amperfy working with credentials it would have got from the old form.
      let credentials: LoginCredentials
      do {
        credentials = try await AlcoveAuth.signIn(email: email, password: password)
      } catch {
        self.showErrorMsg(message: error.localizedDescription)
        return
      }

      var accountInfo = Account.createInfo(credentials: credentials)
      guard !self.appDelegate.storage.settings.accounts.allAccounts
        .contains(where: { $0 == accountInfo })
      else {
        self.showErrorMsg(message: "Account already added!")
        return
      }

      do {
        var credentials = credentials
        let meta = self.appDelegate.getMeta(accountInfo)
        let authenticatedApiType = try await meta.backendApi.login(
          apiType: .subsonic,
          credentials: credentials
        )
        credentials.backendApi = authenticatedApiType
        accountInfo = Account.createInfo(credentials: credentials)
        meta.backendApi.selectedApi = authenticatedApiType
        meta.account.assignInfo(info: accountInfo)
        self.appDelegate.storage.main.saveContext()
        self.appDelegate.storage.settings.accounts.login(credentials)
        meta.backendApi.provideCredentials(credentials: credentials)

        UserDefaults.standard.set(email, forKey: Self.lastEmailKey)
        // Keyed by this account specifically -- configureAlcoveSession() on a
        // TabBarVC for a *different* account must never pick this email up.
        UserDefaults.standard.set(
          email,
          forKey: AlcoveSessionStore.emailDefaultsKey(for: accountInfo.ident)
        )

        self.appDelegate.notificationHandler.post(name: .accountAdded, object: nil, userInfo: nil)
        self.appDelegate.notificationHandler.post(
          name: .accountActiveChanged,
          object: nil,
          userInfo: nil
        )
        AmperfyAppShortcuts.updateAppShortcutParameters()

        let syncVC = AppStoryboard.Main.segueToSync(account: meta.account)
        if let rootVC = self.presentingViewController {
          syncVC.modalPresentationStyle = self.modalPresentationStyle
          rootVC.dismiss(animated: false) {
            rootVC.present(syncVC, animated: false)
          }
        } else {
          guard let mainScene = AppDelegate.mainSceneDelegate else { return }
          mainScene
            .replaceMainRootViewController(vc: syncVC)
        }
      } catch {
        if error is AuthenticationError {
          self.showErrorMsg(message: error.localizedDescription)
        } else {
          self.showErrorMsg(message: "Not able to login!")
        }
        self.appDelegate.resetMeta(accountInfo)
      }
    }
  }

  func showErrorMsg(message: String) {
    let alert = UIAlertController(title: "Login failed", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true, completion: nil)
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemBackground

    brandLabel.translatesAutoresizingMaskIntoConstraints = false
    iconView.translatesAutoresizingMaskIntoConstraints = false
    formGlassContainer.translatesAutoresizingMaskIntoConstraints = false
    loginGlassContainer.translatesAutoresizingMaskIntoConstraints = false
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(brandLabel)
    view.addSubview(iconView)
    view.addSubview(formGlassContainer)
    view.addSubview(loginGlassContainer)
    view.addSubview(closeButton)

    formLeadingConstraing = formGlassContainer.leadingAnchor.constraint(
      equalTo: view.leadingAnchor,
      constant: 12
    )
    formLeadingConstraing?.priority = .defaultHigh
    formTrailingConstraing = formGlassContainer.trailingAnchor.constraint(
      equalTo: view.trailingAnchor,
      constant: -12
    )
    formTrailingConstraing?.priority = .defaultHigh
    formWitdhConstraing = formGlassContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 600)
    formWitdhConstraing?.priority = .required

    iconView.addConstraint(NSLayoutConstraint(
      item: iconView,
      attribute: .height,
      relatedBy: .equal,
      toItem: iconView,
      attribute: .width,
      multiplier: 1.0,
      constant: 0
    ))
    NSLayoutConstraint.activate([
      brandLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
      brandLabel.bottomAnchor.constraint(equalTo: formGlassContainer.topAnchor, constant: -30),
      brandLabel.heightAnchor.constraint(equalToConstant: 60),

      formGlassContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
      formGlassContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 0),
      formWitdhConstraing!,
      formLeadingConstraing!,
      formTrailingConstraing!,

      loginGlassContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
      loginGlassContainer.topAnchor.constraint(
        equalTo: formGlassContainer.bottomAnchor,
        constant: 30
      ),
      loginGlassContainer.widthAnchor.constraint(equalToConstant: 140),
      loginGlassContainer.heightAnchor.constraint(equalToConstant: 40),

      iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0),
      iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 0),
      iconView.heightAnchor.constraint(equalTo: formGlassContainer.heightAnchor, constant: 40),

      // Close button top-right
      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      closeButton.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -16
      ),
    ])

    // Show close button only when presented as a sheet/modal
    let isModal = presentingViewController != nil || navigationController?
      .presentingViewController != nil
    closeButton.isHidden = !isModal
  }

  override func updateProperties() {
    super.updateProperties()

    var outerInset: CGFloat = 25
    if traitCollection.horizontalSizeClass == .compact {
      outerInset = 20
    } else {
      outerInset = 40
    }

    mainContainerPaddingLeadingConstraint?.constant = outerInset
    mainContainerPaddingTrailingConstraint?.constant = -outerInset
    mainContainerPaddingTopConstraint?.constant = outerInset
    mainContainerPaddingBottomConstraint?.constant = -outerInset + 6
  }

  override func viewWillLayoutSubviews() {
    let glassEffect = UIGlassEffect(style: .regular)
    glassEffect.isInteractive = false
    glassEffect.tintColor = appDelegate.storage.settings.accounts.getSetting(nil).read
      .themePreference.asColor
      .withAlphaComponent(0.1)
    formGlassContainer.effect = glassEffect

    if formGlassContainer.frame.width < 600 {
      formLeadingConstraing?.priority = .required
      formTrailingConstraing?.priority = .required
      formWitdhConstraing?.priority = .defaultHigh
    } else {
      formLeadingConstraing?.priority = .defaultHigh
      formTrailingConstraing?.priority = .defaultHigh
      formWitdhConstraing?.priority = .required
    }
  }

  override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    // The stored credentials hold the Subsonic username, which is not what is
    // typed here any more, so the email is remembered separately.
    if emailTF.text?.isEmpty ?? true,
       let last = UserDefaults.standard.string(forKey: Self.lastEmailKey) {
      emailTF.text = last
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    let isModal = presentingViewController != nil || navigationController?
      .presentingViewController != nil
    closeButton.isHidden = !isModal
  }

}
