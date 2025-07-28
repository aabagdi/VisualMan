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
  
  var body: some View {
    VStack {
      Image(uiImage: album.representativeItem?.albumArt ?? UIImage(named: "Art Placeholder")!)
        .resizable()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 250, height: 250)
        .padding()
      Text(album.representativeItem?.albumTitle ?? "Unknown")
        .font(.headline)
      Text(album.representativeItem?.albumArtist ?? "Unknown")
        .font(.subheadline)
      NavigationStack {
        List(album.items.sorted { $0.albumTrackNumber < $1.albumTrackNumber }, id: \.persistentID) { song in
          NavigationLink(destination: MusicPlayerView(song)) {
            HStack {
              Text(String(song.albumTrackNumber))
              Spacer()
              Text(String(song.title ?? "Unknown"))
            }
          }
          .toolbarVisibility(.hidden, for: .tabBar)
        }
      }
    }
  }
}
