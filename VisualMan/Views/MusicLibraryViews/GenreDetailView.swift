//
//  GenreDetailView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct GenreDetailView: View {
  let genre: String
  let albums: [MPMediaItemCollection]

  var body: some View {
    List(albums, id: \.persistentID) { album in
      NavigationLink {
        AlbumDetailView(album: album)
      } label: {
        AlbumRowView(album: album)
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .modifier(SettingsToolbarButton())
    .navigationTitle(genre)
  }
}
