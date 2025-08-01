//
//  MusicLibraryView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/7/25.
//

import SwiftUI
import MediaPlayer

struct MusicLibraryView: View {
  @EnvironmentObject private var musicLibraryManager: MusicLibraryAccessManager
  
  var body: some View {
    AlbumListView(albums: musicLibraryManager.albums)
  }
}
