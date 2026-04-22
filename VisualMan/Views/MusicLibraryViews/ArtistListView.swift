//
//  ArtistListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

private struct ArtistSelection: Hashable {
  let artistName: String
}

struct ArtistListView: View {
  @State private var searchText: String = ""
  @State private var filteredArtists: [MPMediaItemCollection]?

  let artists: [MPMediaItemCollection]
  let albums: [MPMediaItemCollection]

  private var displayedArtists: [MPMediaItemCollection] {
    filteredArtists ?? artists
  }

  var body: some View {
    Section {
      if !artists.isEmpty {
        List(displayedArtists, id: \.representativeItem?.persistentID) { artist in
          NavigationLink(value: ArtistSelection(artistName: artist.representativeItem?.artist ?? "")) {
            Text(artist.representativeItem?.artist ?? "Unknown")
          }
        }
        .navigationDestination(for: ArtistSelection.self) { selection in
          ArtistDetailView(albums: albums.filter { album in
            album.representativeItem?.artist == selection.artistName
          })
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .task(id: searchText) {
          if searchText.isEmpty {
            filteredArtists = nil
            return
          }
          try? await Task.sleep(for: .milliseconds(300))
          filteredArtists = artists.filtered(by: searchText) {
            [$0.representativeItem?.artist]
          }
        }
      } else {
        Text("No artists found!")
          .font(.caption)
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .navigationTitle("Artists")
  }
}
