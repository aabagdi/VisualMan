//
//  ArtistListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct ArtistListView: View {
  @State private var searchText: String = ""
  @State private var filteredArtists: [MPMediaItemCollection]?

  let artists: [MPMediaItemCollection]
  let albums: [MPMediaItemCollection]

  private var displayedArtists: [MPMediaItemCollection] {
    filteredArtists ?? artists
  }

  var body: some View {
    Group {
      if !artists.isEmpty {
        List(displayedArtists, id: \.representativeItem?.persistentID) { artist in
          let artistName = artist.representativeItem?.artist ?? "Unknown"
          NavigationLink(destination: ArtistDetailView(artistName: artistName,
                                                       albums: albums(for: artist))) {
            Text(artistName)
          }
        }
        .debouncedSearchable(text: $searchText, results: $filteredArtists, source: artists) {
          [$0.representativeItem?.artist]
        }
      } else {
        Text("No artists found!")
          .font(.caption)
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .navigationTitle("Artists")
  }

  private func albums(for artist: MPMediaItemCollection) -> [MPMediaItemCollection] {
    let albumIDs = Set(artist.items.map(\.albumPersistentID))
    return albums.filter { album in
      guard let albumID = album.representativeItem?.albumPersistentID else { return false }
      return albumIDs.contains(albumID)
    }
  }
}
