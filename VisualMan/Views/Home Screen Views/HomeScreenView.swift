//
//  HomeScreenView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/19/25.
//

import SwiftUI

struct HomeScreenView: View {
  var body: some View {
    TabView {
      Tab("Music Library", systemImage: "music.note.square.stack.fill") {
        MusicLibraryView()
      }
      
      Tab("Files", systemImage: "folder.fill") {
        FilesTabView()
      }
    }
  }
}
