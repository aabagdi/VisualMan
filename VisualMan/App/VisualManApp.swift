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
  @State private var musicLibraryManager = MusicLibraryAccessManager()
  @State private var playlistManager = AudioPlaylistManager()
  
  @Dependency(AudioEngineManager.self) private var audioEngineManager
  
  var body: some Scene {
    WindowGroup {
      HomeScreenView()
        .onAppear {
          musicLibraryManager.requestMusicLibraryAccess()
        }
      .environment(musicLibraryManager)
      .environment(playlistManager)
      .environment(audioEngineManager)
    }
  }
}
