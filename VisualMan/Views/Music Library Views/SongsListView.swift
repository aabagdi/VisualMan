//
//  SongsListView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/30/25.
//

import SwiftUI
import MediaPlayer

struct SongsListView: View {
  let songs: [MPMediaItem]
  
  var body: some View {
    NavigationStack {
      List(songs.enumerated(), id: \.element.persistentID) { index, song in
        NavigationLink(destination: MusicPlayerView(songs, startingIndex: index)) {
          Text(song.title ?? "Unknown")
        }
        .toolbarVisibility(.hidden, for: .tabBar)
      }
    }
  }
}
