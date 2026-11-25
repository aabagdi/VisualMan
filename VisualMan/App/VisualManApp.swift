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
        .task {
          await musicLibraryManager.requestMusicLibraryAccess()
        }
        .task { await powerStateChanged() }
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

  private func powerStateChanged() async {
    showLowPowerAlert = ProcessInfo.processInfo.isLowPowerModeEnabled
    for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
      showLowPowerAlert = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
  }
}
