//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer

struct MusicPlayerView: View {
  @State private var failedPlaying: Bool = false
  
  @ObservedObject private var audioManager = AudioEngineManager.shared
  
  let audioSource: any AudioSource
  
  init(_ audioSource: AudioSource) {
   self.audioSource = audioSource
  }
  
  init(fileURL: URL, title: String? = nil) {
    self.audioSource = FileAudioSource(url: fileURL, title: title)
  }
  
  var body: some View {
    ZStack {
      CircleVisualizerView(audioLevels: audioManager.audioLevels)
        .ignoresSafeArea()
      VStack {
        Spacer()
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
          do {
            try audioManager.play(audioSource)
          } catch {
            failedPlaying.toggle()
          }
        }
        .onDisappear {
          audioManager.stop()
        }
      }
    }
  }
}
