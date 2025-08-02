//
//  PlaylistDetailView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import MediaPlayer

struct PlaylistDetailView: View {
  let playlist: MPMediaItemCollection
  
  var body: some View {
    NavigationStack {
      List(playlist.items.enumerated(), id: \.1.persistentID) { index, song in
        NavigationLink(destination: MusicPlayerView(playlist.items, startingIndex: index)) {
          VStack(alignment: .leading) {
            Text(song.title ?? "Unknown")
              .font(.headline)
            Text(song.artist ?? "Unknown")
              .font(.caption2)
          }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
      }
    }
    .navigationTitle(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Unknown")
  }
}
