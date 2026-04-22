//
//  AlbumListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/28/25.
//

import SwiftUI
import MediaPlayer

struct AlbumListView: View {
  @State private var searchText: String = ""
  @State private var filteredAlbums: [MPMediaItemCollection]?
  
  @Environment(MusicLibraryAccessManager.self) private var library
  
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
                NavigationLink(destination: SongsListView(songs: library.songs)) {
                  HStack {
                    Image(systemName: "music.note")
                      .font(.system(size: 20))
                      .frame(width: 30, height: 30)
                      .padding(.trailing, 8)
                    
                    Text("Songs")
                    
                    Spacer()
                    
                    Text("\(library.songs.count)")
                      .foregroundStyle(.secondary)
                      .font(.system(size: 15))
                  }
                  .padding(.vertical, 4)
                }
                
                NavigationLink(destination: ArtistListView(artists: library.artists, albums: library.albums)) {
                  HStack {
                    Image(systemName: "music.microphone")
                      .font(.system(size: 20))
                      .frame(width: 30, height: 30)
                      .padding(.trailing, 8)
                    
                    Text("Artists")
                    
                    Spacer()
                    
                    Text("\(library.artists.count)")
                      .foregroundStyle(.secondary)
                      .font(.system(size: 15))
                  }
                  .padding(.vertical, 4)
                }
                
                NavigationLink(destination: GenreListView(genres: library.genres, albums: library.albums)) {
                  HStack {
                    Image(systemName: "guitars.fill")
                      .font(.system(size: 20))
                      .frame(width: 30, height: 30)
                      .padding(.trailing, 8)
                    
                    Text("Genres")
                    
                    Spacer()
                    
                    Text("\(library.genres.count)")
                      .foregroundStyle(.secondary)
                      .font(.system(size: 15))
                  }
                  .padding(.vertical, 4)
                }
                
                NavigationLink(destination: PlaylistListView(playlists: library.playlists)) {
                  HStack {
                    Image(systemName: "list.number")
                      .font(.system(size: 20))
                      .frame(width: 30, height: 30)
                      .padding(.trailing, 8)
                    
                    Text("Playlists")
                    
                    Spacer()
                    
                    Text("\(library.playlists.count)")
                      .foregroundStyle(.secondary)
                      .font(.system(size: 15))
                  }
                  .padding(.vertical, 4)
                }
                
                NavigationLink(destination: CompilationListView(compilations: library.compilations)) {
                  HStack {
                    Image(systemName: "person.2.crop.square.stack.fill")
                      .font(.system(size: 20))
                      .frame(width: 30, height: 30)
                      .padding(.trailing, 8)
                    
                    Text("Compilations")
                    
                    Spacer()
                    
                    Text("\(library.compilations.count)")
                      .foregroundStyle(.secondary)
                      .font(.system(size: 15))
                  }
                  .padding(.vertical, 4)
                }
              }
            }
            
            Section {
              if !albums.isEmpty {
                ForEach(displayedAlbums, id: \.persistentID) { album in
                  NavigationLink(destination: AlbumDetailView(album: album)) {
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
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
      .task(id: searchText) {
        if searchText.isEmpty {
          filteredAlbums = nil
          return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        filteredAlbums = albums.filtered(by: searchText) {
          [$0.representativeItem?.albumTitle, $0.representativeItem?.artist]
        }
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
