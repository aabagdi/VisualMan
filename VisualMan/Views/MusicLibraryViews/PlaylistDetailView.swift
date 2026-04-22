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
  
  @Environment(AudioEngineManager.self) private var audioManager
  
  var body: some View {
    List(playlist.items.enumerated(), id: \.1.persistentID) { index, song in
      let isCurrentSong = song.assetURL == audioManager.currentAudioSourceURL
      NavigationLink(destination: MusicPlayerView(playlist.items, startingIndex: index)) {
        HStack(spacing: 10) {
          if isCurrentSong {
            NowPlayingIndicatorView(isAnimating: audioManager.isPlaying)
              .foregroundStyle(.tint)
          }
          VStack(alignment: .leading) {
            Text(song.title ?? "Unknown")
              .font(.headline)
              .foregroundStyle(isCurrentSong ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            Text(song.artist ?? "Unknown")
              .font(.caption2)
          }
        }
      }
    }
    .navigationTitle(playlist.value(forProperty: MPMediaPlaylistPropertyName) as? String ?? "Unknown")
    .toolbarVisibility(.hidden, for: .tabBar)
  }
}
