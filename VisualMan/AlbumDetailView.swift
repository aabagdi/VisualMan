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
  
  private var year: String {
    if let year = album.representativeItem?.value(forProperty: "year") as? Int {
      return String(year)
    } else {
      return "Unknown"
    }
  }
  
  private var sortedSongs: [MPMediaItem] {
    album.items.sorted { $0.albumTrackNumber < $1.albumTrackNumber }
  }
  
  var body: some View {
    VStack {
      Image(uiImage: album.representativeItem?.albumArt ?? UIImage(named: "Art Placeholder")!)
        .resizable()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 250, height: 250)
        .padding()
      Text(album.representativeItem?.albumTitle ?? "Unknown")
        .font(.headline)
      if album.representativeItem?.isCompilation == true {
        Text("Various Artists")
          .font(.subheadline)
      } else {
        Text(album.representativeItem?.albumArtist ?? "Unknown")
          .font(.subheadline)
      }
      HStack {
        Text(album.representativeItem?.genre ?? "Unknown")
        Text("•")
        Text(year)
      }
      .font(.footnote)
      NavigationStack {
        List(sortedSongs.enumerated(), id: \.element.persistentID) { index, song in
          NavigationLink(destination: MusicPlayerView(sortedSongs, startingIndex: index)) {
            HStack {
              Text(String(song.albumTrackNumber))
              Spacer()
              Text(String(song.title ?? "Unknown"))
                .minimumScaleFactor(0.05)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity)
            }
          }
          .toolbarVisibility(.hidden, for: .tabBar)
        }
      }
    }
  }
}
