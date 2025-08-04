//
//  HomeScreenView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI

struct HomeScreenView: View {
  @Environment(MusicLibraryAccessManager.self) private var library
  
  var body: some View {
    TabView {
      Tab("Music Library", systemImage: "music.note.square.stack.fill") {
        AlbumListView(albums: library.albums)
      }
      
      Tab("Files", systemImage: "folder.fill") {
        FilesTabView()
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      //MusicPlayerTabView()
    }
  }
}
