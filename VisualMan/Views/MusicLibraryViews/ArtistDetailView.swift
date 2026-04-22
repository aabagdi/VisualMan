//
//  ArtistDetailView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct ArtistDetailView: View {
  let albums: [MPMediaItemCollection]

  var body: some View {
    List(albums, id: \.representativeItem?.persistentID) { album in
      NavigationLink(destination: AlbumDetailView(album: album)) {
        AlbumRowView(album: album)
      }
    }
    .navigationTitle(albums.first?.representativeItem?.artist ?? "Unknown")
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
