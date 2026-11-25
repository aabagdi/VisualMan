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

  var body: some View {
    Group {
      if !genres.isEmpty {
        List(displayedGenres, id: \.representativeItem?.persistentID) { genre in
          let genreName = genre.representativeItem?.genre ?? String(localized: "Unknown")
          NavigationLink {
            GenreDetailView(genre: genreName, albums: albums(for: genre))
          } label: {
            Text(genreName)
          }
        }
        .debouncedSearchable(text: $searchText, results: $filteredGenres, source: genres) {
          [$0.representativeItem?.genre]
        }
      } else {
        ContentUnavailableView("No Genres", systemImage: "guitars.fill",
                               description: Text("Your music library has no genres."))
      }
    }
    .toolbarVisibility(.hidden, for: .tabBar)
    .modifier(SettingsToolbarButton())
    .navigationTitle("Genres")
  }

  private func albums(for genre: MPMediaItemCollection) -> [MPMediaItemCollection] {
    let genreName = genre.representativeItem?.genre
    return albums.filter { $0.representativeItem?.genre == genreName }
  }
}
