//
//  AlbumDetailView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/28/25.
//

import SwiftUI
import MediaPlayer

struct AlbumDetailView: View {
  let album: MPMediaItemCollection
  
  private let placeholder = UIImage(named: "Art Placeholder")!
  
  private var year: String {
    if let year = album.representativeItem?.value(forProperty: "year") as? Int {
      return String(year)
    } else {
      return "Unknown"
    }
  }
  
  private var sortedSongs: [MPMediaItem] {
    album.items.sorted { ($0.discNumber, $0.albumTrackNumber) < ($1.discNumber, $1.albumTrackNumber) }
  }
  
  var body: some View {
    let albumArt = album.representativeItem?.albumArt ?? placeholder
    
    List {
      Section {
        VStack(spacing: 12) {
          Image(uiImage: albumArt)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 4)
            .frame(maxWidth: 300)
          
          VStack(spacing: 4) {
            Text(album.representativeItem?.albumTitle ?? "Unknown")
              .font(.title2)
              .fontWeight(.semibold)
              .multilineTextAlignment(.center)
            
            if album.representativeItem?.isCompilation == true {
              Text("Various Artists")
                .font(.body)
                .foregroundColor(.secondary)
            } else {
              Text(album.representativeItem?.albumArtist ?? "Unknown")
                .font(.body)
                .foregroundColor(.secondary)
            }
            
            HStack {
              Text(album.representativeItem?.genre ?? "Unknown")
              Text("•")
              Text(year)
            }
            .font(.caption)
            .foregroundColor(.secondary)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }
      
      Section {
        ForEach(Array(sortedSongs.enumerated()), id: \.element.persistentID) { index, song in
          NavigationLink(destination: MusicPlayerView(sortedSongs, startingIndex: index)) {
            HStack(spacing: 12) {
              Text("\(song.albumTrackNumber)")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .frame(minWidth: 20, alignment: .trailing)
              
              VStack(alignment: .leading, spacing: 2) {
                Text(song.title ?? "Unknown")
                  .font(.system(size: 16))
                  .lineLimit(1)
                
                if album.representativeItem?.isCompilation == true,
                   let artist = song.artist {
                  Text(artist)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
              }
              
              Spacer()
              
              if let duration = formatDuration(song.playbackDuration) {
                Text(duration)
                  .font(.system(size: 14))
                  .foregroundColor(.secondary)
              }
            }
            .padding(.vertical, 4)
          }
          .toolbarVisibility(.hidden, for: .tabBar)
        }
      }
    }
    .listStyle(InsetGroupedListStyle())
    .navigationBarTitleDisplayMode(.inline)
  }
  
  private func formatDuration(_ duration: TimeInterval) -> String? {
    guard duration > 0 else { return nil }
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
