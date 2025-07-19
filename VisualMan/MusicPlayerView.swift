//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer

struct MusicPlayerView: View {
  let audioSource: any AudioSource
  @ObservedObject private var audioManager = AudioEngineManager.shared
  
  init(_ audioSource: AudioSource) {
   self.audioSource = audioSource
  }
  
  init(fileURL: URL, title: String? = nil) {
    self.audioSource = FileAudioSource(url: fileURL, title: title)
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
     audioManager.play(audioSource)
    }
    .onDisappear {
      audioManager.stop()
    }
  }
}
