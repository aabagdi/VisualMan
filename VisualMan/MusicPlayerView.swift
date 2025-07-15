//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer

struct MusicPlayerView: View {
  var song: MPMediaItem
  @StateObject private var audioManager = AudioEngineManager()
  
  init(_ song: MPMediaItem) {
   self.song = song
  }
  
  var body: some View {
    HStack {
      Button {
        
      } label: {
        Image(systemName: "backward.fill")
      }
      Spacer()
      Button {
        if audioManager.isPlaying {
          audioManager.pause()
        } else {
          audioManager.resume()
        }
      } label: {
        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
      }
      Spacer()
      Button {
        
      } label: {
        Image(systemName: "forward.fill")
      }
    }
    .padding()
    .onAppear {
     audioManager.play(song)
    }
  }
}
