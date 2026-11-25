//
//  AlbumListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/28/25.
//

import SwiftUI
import Dependencies
import MediaPlayer

struct AlbumListView: View {
  @State private var searchText: String = ""
  @State private var filteredAlbums: [MPMediaItemCollection]?

  @Dependency(MusicLibraryAccessManager.self) private var library
  
  let albums: [MPMediaItemCollection]

  private var displayedAlbums: [MPMediaItemCollection] {
    filteredAlbums ?? albums
  }
  
  var body: some View {
    switch library.authorizationStatus {
    case .authorized, .restricted:
      Group {
        if library.isLoading && library.albums.isEmpty {
          LibraryLoadingView()
        } else if !library.albums.isEmpty {
          List {
            if searchText.isEmpty {
              Section {
                NavigationLink {
                  SongsListView(songs: library.songs)
                } label: {
                  LibraryCategoryRow(title: "Songs", systemImage: "music.note", count: library.songs.count)
                }

                NavigationLink {
                  ArtistListView(artists: library.artists, albums: library.albums + library.compilations)
                } label: {
                  LibraryCategoryRow(title: "Artists", systemImage: "music.microphone", count: library.artists.count)
                }

                NavigationLink {
                  GenreListView(genres: library.genres, albums: library.albums)
                } label: {
                  LibraryCategoryRow(title: "Genres", systemImage: "guitars.fill", count: library.genres.count)
                }

                NavigationLink {
                  PlaylistListView(playlists: library.playlists)
                } label: {
                  LibraryCategoryRow(title: "Playlists", systemImage: "list.number", count: library.playlists.count)
                }

                NavigationLink {
                  CompilationListView(compilations: library.compilations)
                } label: {
                  LibraryCategoryRow(title: "Compilations",
                                     systemImage: "person.2.crop.square.stack.fill",
                                     count: library.compilations.count)
                }
              }
            }
            
            Section {
              if !displayedAlbums.isEmpty {
                ForEach(displayedAlbums, id: \.persistentID) { album in
                  NavigationLink {
                    AlbumDetailView(album: album)
                  } label: {
                    AlbumRowView(album: album)
                  }
                }
              } else {
                Text("No albums found!")
                  .font(.caption)
              }
            }
          }
        } else {
          ContentUnavailableView("No Albums", systemImage: "music.note.list",
                                 description: Text("Your music library is empty."))
        }
      }
      .listStyle(.insetGrouped)
      .debouncedSearchable(text: $searchText, results: $filteredAlbums, source: albums) {
        [$0.representativeItem?.albumTitle, $0.representativeItem?.albumArtist, $0.representativeItem?.artist]
      }
      .navigationTitle("Library")
    case .denied, .notDetermined:
      ContentUnavailableView {
        Label("Music library access not authorized", systemImage: "music.note.list")
      } description: {
        Text("Please enable music library permissions for VisualMan in System Settings")
      }
    @unknown default:
      ContentUnavailableView {
        Label("Unknown state", systemImage: "music.note.list")
      } description: {
        Text("An unknown error occurred. Please try again.")
      }
    }
  }
}

private struct LibraryCategoryRow: View {
  let title: LocalizedStringKey
  let systemImage: String
  let count: Int

  @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 30

  var body: some View {
    HStack {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(width: iconSize, height: iconSize)
        .padding(.trailing, 8)
        .accessibilityHidden(true)

      Text(title)

      Spacer()

      Text("\(count)")
        .foregroundStyle(.secondary)
        .font(.subheadline)
    }
    .padding(.vertical, 4)
  }
}
