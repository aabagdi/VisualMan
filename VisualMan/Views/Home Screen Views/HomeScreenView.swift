//
//  HomeScreenView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI

struct HomeScreenView: View {
  @Environment(MusicLibraryAccessManager.self) private var library
  
  @State private var isShowingBarPlayer: Bool = true
  @State private var audioManager = AudioEngineManager.shared
  @State private var isShowingMusicPlayer = false
  @State private var playlistManager = AudioPlaylistManager()
  
  var body: some View {
    TabView {
      Tab("Music Library", systemImage: "music.note.list") {
        NavigationStack {
          AlbumListView(albums: library.albums)
            .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                if audioManager.isPlaying || audioManager.currentTime > 0 {
                  NavigationLink("Visualizer") {
                    MusicPlayerView(playlistManager.audioSources, startingIndex: playlistManager.currentIndex)
                  }
                }
              }
            }
        }
      }
      
      Tab("Files", systemImage: "folder.fill") {
        NavigationStack {
          FilesTabView()
        }
      }
    }
    .environment(playlistManager)
  }
}
