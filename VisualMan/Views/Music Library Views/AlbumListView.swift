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
  @Environment(MusicLibraryAccessManager.self) private var library

  let albums: [MPMediaItemCollection]
  
  private let placeholder = UIImage(named: "Art Placeholder")!
  
  private var searchResults: [MPMediaItemCollection] {
    if searchText.isEmpty {
      return albums
    } else {
      return albums.filter { $0.representativeItem?.albumTitle?.localizedCaseInsensitiveContains(searchText) ?? false || $0.representativeItem?.artist?.localizedCaseInsensitiveContains(searchText) ?? false }
    }
  }
  
  var body: some View {
    NavigationStack {
      List {
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
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
                .font(.system(size: 15))
            }
            .padding(.vertical, 4)
          }

          NavigationLink(destination: PlaylistListView(playlists: library.playlists)) {
            HStack {
              Image(systemName: "music.note.list")
                .font(.system(size: 20))
                .frame(width: 30, height: 30)
                .padding(.trailing, 8)
              
              Text("Playlists")
              
              Spacer()
              
              Text("\(library.playlists.count)")
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)
                .font(.system(size: 15))
            }
            .padding(.vertical, 4)
          }
        }
        Section {
          if !albums.isEmpty {
            ForEach(searchResults, id: \.persistentID) { album in
              NavigationLink(destination: AlbumDetailView(album: album)) {
                HStack {
                  Image(uiImage: album.representativeItem?.albumArt ?? placeholder)
                    .resizable()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(width: 60, height: 60)
                  
                  VStack(alignment: .leading, spacing: 2) {
                    Text(album.representativeItem?.albumTitle ?? "Unknown")
                      .font(.system(size: 16))
                      .foregroundColor(.primary)
                      .lineLimit(1)
                    
                    if album.representativeItem?.isCompilation == true {
                      Text("Various Artists")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    } else {
                      Text(album.representativeItem?.albumArtist ?? "Unknown")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                  }
                  .padding(.leading, 8)
                  
                  Spacer()
                }
                .padding(.vertical, 2)
              }
            }
          } else {
            Text("No albums found!")
              .font(.caption)
          }
        }
      }
      .listStyle(InsetGroupedListStyle())
      .navigationTitle("Library")
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
    }
  }
}
