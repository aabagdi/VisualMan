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
  @Dependency(AudioEngineManager.self) private var audioEngineManager
  @State private var musicLibraryManager = MusicLibraryAccessManager()
  @State private var playlistManager = AudioPlaylistManager()
  
  var body: some Scene {
    WindowGroup {
      HomeScreenView()
        .environment(musicLibraryManager)
        .environment(playlistManager)
        .environment(audioEngineManager)
        .onAppear {
          musicLibraryManager.requestMusicLibraryAccess()
        }
    }
  }
}
