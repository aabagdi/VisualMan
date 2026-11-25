//
//  ExternalDisplaySceneDelegate.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/20/26.
//

import SwiftUI
import Dependencies

final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
  @Dependency(ExternalDisplayManager.self) private var externalDisplay

  var window: UIWindow?

  func scene(_ scene: UIScene,
             willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    let controller = UIHostingController(rootView: ExternalDisplayView())
    controller.view.backgroundColor = .black
    window.rootViewController = controller
    window.isHidden = false
    self.window = window
    externalDisplay.sceneConnected()
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    externalDisplay.sceneDisconnected()
    window?.isHidden = true
    window = nil
  }
}
