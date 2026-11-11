//
//  PlaylistDetailView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import SwiftUI
import Dependencies
import MediaPlayer

struct PlaylistDetailView: View {
  let playlist: MPMediaItemCollection
  
  @Dependency(AudioEngineManager.self) private var audioManager
  
  var body: some View {
    List(playlist.items.enumerated(), id: \.1.persistentID) { index, song in
      let isCurrentSong = song.assetURL == audioManager.currentAudioSourceURL
      NavigationLink(destination: MusicPlayerView(playlist.items, startingIndex: index)) {
        SongRowView(song: song, isCurrentSong: isCurrentSong, isPlaying: audioManager.isPlaying)
      }
    }
    .navigationTitle(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Unknown")
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
