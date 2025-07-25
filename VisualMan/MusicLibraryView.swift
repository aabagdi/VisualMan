//
//  MusicLibraryView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/7/25.
//

import SwiftUI
import MediaPlayer

struct MusicLibraryView: View {
  @StateObject private var libraryManager = MusicLibraryAccessManager()
  var body: some View {
    NavigationStack {
      VStack {
        List(libraryManager.songs, id: \.persistentID) { song in
          NavigationLink(song.title ?? "Unknown", value: song)
        }
      }
      .navigationDestination(for: MPMediaItem.self) { song in
        MusicPlayerView(song)
          .toolbarVisibility(.hidden, for: .tabBar)
      }
    }
    .padding()
    .onAppear {
      libraryManager.requestMusicLibraryAccess()
    }
  }
}
