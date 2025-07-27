//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer

struct MusicPlayerView: View {
  enum Visualizers: String, CaseIterable {
    case julia = "Julia Set"
    case fireworks = "Fireworks"
    case interference = "Interference Pattern"
  }
  
  @State private var currentVisualizer = Visualizers.julia
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
      currentShader(currentVisualizer: currentVisualizer, audioLevels: audioManager.audioLevels)
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
    .toolbar {
      Picker("Current Visualizer", selection: $currentVisualizer) {
        ForEach(Visualizers.allCases, id: \.self) { type in
          Text(type.rawValue)
            .tag(type)
        }
      }
      .fixedSize()
    }
  }
  
  @ViewBuilder
  private func currentShader(currentVisualizer: Visualizers, audioLevels: [Float]) -> some View {
    switch currentVisualizer {
    case .julia:
      JuliaVisualizerView(audioLevels: audioLevels)
    case .fireworks:
      FireworksVisualizerView(audioLevels: audioLevels)
    case .interference:
      InterferenceVisualizerView(audioLevels: audioLevels)
    }
  }
}
