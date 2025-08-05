//
//  HomeScreenView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI

struct HomeScreenView: View {
  @Environment(MusicLibraryAccessManager.self) private var library
  @State private var isShowingBar: Bool = true
  
  var body: some View {
    TabView {
      Tab("Music Library", systemImage: "music.note.square.stack.fill") {
        AlbumListView(albums: library.albums)
      }
      
      Tab("Files", systemImage: "folder.fill") {
        FilesTabView()
      }
    }
    .onPreferenceChange(BooleanPreferenceKey.self) { value in
      isShowingBar = value
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      switch isShowingBar {
      case true:
        MusicPlayerTabView()
      case false:
        EmptyView()
      }
    }
  }
}
