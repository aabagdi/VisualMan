//
//  VisualManApp.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/7/25.
//

import SwiftUI

@main
struct VisualManApp: App {
  @State private var musicLibraryManager = MusicLibraryAccessManager()
  @State private var playlistManager = AudioPlaylistManager()
  
  var body: some Scene {
    WindowGroup {
      HomeScreenView()
        .environment(musicLibraryManager)
        .environment(playlistManager)
        .onAppear {
          musicLibraryManager.requestMusicLibraryAccess()
        }
    }
  }
}
