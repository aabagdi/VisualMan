//
//  GenreListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct GenreListView: View {
  @State private var searchText: String = ""
  @State private var filteredGenres: [MPMediaItemCollection]?
  
  let genres: [MPMediaItemCollection]
  let albums: [MPMediaItemCollection]
  
  private var displayedGenres: [MPMediaItemCollection] {
    filteredGenres ?? genres
  }

  private var albumsByGenre: [String: [MPMediaItemCollection]] {
    Dictionary(grouping: albums) { $0.representativeItem?.genre ?? "Unknown" }
  }

  var body: some View {
    Section {
      if !genres.isEmpty {
        List(displayedGenres, id: \.representativeItem?.persistentID) { genre in
          let genreName = genre.representativeItem?.genre ?? "Unknown"
          let genreAlbums = albumsByGenre[genreName] ?? []
          NavigationLink(destination: GenreDetailView(genre: genreName, albums: genreAlbums)) {
            Text(genre.representativeItem?.genre ?? "Unknown")
          }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .task(id: searchText) {
          if searchText.isEmpty {
            filteredGenres = nil
            return
          }
          try? await Task.sleep(for: .milliseconds(300))
          filteredGenres = genres.filtered(by: searchText) {
            [$0.representativeItem?.genre]
          }
        }
        .navigationTitle("Genres")
      } else {
        Text("No genres found!")
          .font(.caption)
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
