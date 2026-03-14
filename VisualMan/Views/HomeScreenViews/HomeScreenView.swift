//
//  HomeScreenView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI

struct HomeScreenView: View {
  @State private var isShowingBarPlayer: Bool = true
  @State private var isShowingMusicPlayer = false
  
  @Environment(AudioEngineManager.self) private var audioManager
  @Environment(MusicLibraryAccessManager.self) private var library
  @Environment(AudioPlaylistManager.self) private var playlistManager
  
  var body: some View {
    TabView {
      Tab("Music Library", systemImage: "music.note.list") {
        NavigationStack {
          AlbumListView(albums: library.albums)
            .toolbar {
              ToolbarItem(placement: .navigationBarTrailing) {
                if audioManager.isPlaying || audioManager.currentTime > 0 {
                  NavigationLink(destination: MusicPlayerView(playlistManager.audioSources, startingIndex: playlistManager.currentIndex)) {
                    Image(systemName: "play.fill")
                  }
                }
              }
            }
        }
      }
      
      Tab("Files", systemImage: "folder.fill") {
        NavigationStack {
          FilesTabView()
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea()
        }
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
  }
}
