//
//  HomeScreenView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI

private struct NowPlayingDestination: Hashable {}

struct HomeScreenView: View {
  @State private var selectedTab: VMTab = .musicLibrary
  @State private var visualizerSelection = VisualizerSelection()
  
  @Environment(AudioEngineManager.self) private var audioManager
  @Environment(MusicLibraryAccessManager.self) private var library
  @Environment(AudioPlaylistManager.self) private var playlistManager
  
  private enum VMTab {
    case musicLibrary
    case files
  }
  
  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Music Library", systemImage: "music.note.list", value: .musicLibrary) {
        NavigationStack {
          AlbumListView(albums: library.albums)
            .navigationDestination(for: NowPlayingDestination.self) { _ in
              MusicPlayerView(playlistManager.audioSources,
                              startingIndex: playlistManager.currentIndex)
            }
            .toolbar {
              ToolbarItem(placement: .topBarLeading) {
                NavigationLink("Credits", destination: CreditsView())
              }
              ToolbarItem(placement: .topBarTrailing) {
                if audioManager.isPlaying || audioManager.currentTime > 0 {
                  NavigationLink(value: NowPlayingDestination()) {
                    Image(systemName: "play.fill")
                  }
                }
              }
            }
        }
      }
      
      Tab("Files", systemImage: "folder.fill", value: .files) {
        NavigationStack {
          FilesTabView()
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
        }
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .environment(visualizerSelection)
  }
}
