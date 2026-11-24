//
//  VisualManApp.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/7/25.
//

import SwiftUI
import UIKit
import Dependencies

@main
struct VisualManApp: App {
  @State private var showLowPowerAlert = false

  @Dependency(MusicLibraryAccessManager.self) private var musicLibraryManager
  @Dependency(VisualizerRendererCache.self) private var rendererCache

  var body: some Scene {
    WindowGroup {
      HomeScreenView()
        .onAppear {
          musicLibraryManager.requestMusicLibraryAccess()
          if ProcessInfo.processInfo.isLowPowerModeEnabled {
            showLowPowerAlert = true
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
          showLowPowerAlert = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.willConnectNotification)) { note in
          let scene = note.object as? UIScene
          print("[ExternalDisplay] scene willConnect role=\(scene?.session.role.rawValue ?? "nil") delegate=\(String(describing: scene?.delegate))")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
          let roles = UIApplication.shared.connectedScenes.map { $0.session.role.rawValue }
          let config = Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") ?? "missing"
          print("[ExternalDisplay] active; scenes=\(roles) manifest=\(config)")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
          rendererCache.purge()
        }
        .alert("Low Power Mode Enabled", isPresented: $showLowPowerAlert) {
          Button("OK") { }
        } message: {
          Text("VisualMan performs best with Low Power Mode turned off.")
        }
        .environment(rendererCache)
    }
  }
}
