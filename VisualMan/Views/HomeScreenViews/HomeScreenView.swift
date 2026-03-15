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
  @State private var selectedTab: VMTab = .musicLibrary
  
  @Environment(AudioEngineManager.self) private var audioManager
  @Environment(MusicLibraryAccessManager.self) private var library
  @Environment(AudioPlaylistManager.self) private var playlistManager
  
  enum VMTab {
    case musicLibrary
    case files
  }
  
  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Music Library", systemImage: "music.note.list", value: .musicLibrary) {
        AlbumListView(albums: library.albums)
      }
      
      Tab("Files", systemImage: "folder.fill", value: .files) {
        FilesTabView()
          .ignoresSafeArea()
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .navigationTitle(selectedTab == .musicLibrary ? "Library" : "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(selectedTab == .musicLibrary ? .visible : .hidden, for: .navigationBar)
    .toolbar {
      if selectedTab == .musicLibrary {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink("Credits", destination: CreditsView())
        }
        
        ToolbarItem(placement: .topBarTrailing) {
          if audioManager.isPlaying || audioManager.currentTime > 0 {
            NavigationLink(destination: MusicPlayerView(playlistManager.audioSources, startingIndex: playlistManager.currentIndex)) {
              Image(systemName: "play.fill")
            }
          }
        }
      }
    }
  }
}
