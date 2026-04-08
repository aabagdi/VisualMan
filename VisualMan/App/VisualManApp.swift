//
//  VisualManApp.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/7/25.
//

import SwiftUI
import Dependencies

@main
struct VisualManApp: App {
  @State private var showLowPowerAlert = false
  
  @Dependency(AudioEngineManager.self) private var audioEngineManager
  @Dependency(AudioPlaylistManager.self) private var playlistManager
  @Dependency(MusicLibraryAccessManager.self) private var musicLibraryManager
  
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
          if ProcessInfo.processInfo.isLowPowerModeEnabled {
            showLowPowerAlert = true
          }
        }
        .alert("Low Power Mode Enabled", isPresented: $showLowPowerAlert) {
          Button("OK") { }
        } message: {
          Text("VisualMan performs best with Low Power Mode turned off.")
        }
        .environment(musicLibraryManager)
        .environment(playlistManager)
        .environment(audioEngineManager)
    }
  }
}
