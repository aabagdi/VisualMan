//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer

struct MusicPlayerView: View {
  private var sliderColor: Color = .white
  private var normalFillColor: Color {
    sliderColor.opacity(0.5)
  }
  private var emptyColor: Color {
    sliderColor.opacity(0.3)
  }
  
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
        ProgressSliderView(value: $audioManager.currentTime,
                           inRange: TimeInterval.zero...max(audioManager.duration, 0.1),
                           activeFillColor: sliderColor,
                           fillColor: normalFillColor,
                           emptyColor: emptyColor,
                           height: 8) { started in
          if !started {
            audioManager.seek(to: audioManager.currentTime)
          }
        }
        .padding()
        HStack {
          Button {
            
          } label: {
            Image(systemName: "backward")
              .foregroundStyle(normalFillColor)
          }
          Spacer()
          Button {
            if audioManager.isPlaying {
              audioManager.pause()
            } else {
              audioManager.resume()
            }
          } label: {
            Image(systemName: audioManager.isPlaying ? "pause" : "play")
              .foregroundStyle(normalFillColor)
          }
          Spacer()
          Button {
            
          } label: {
            Image(systemName: "forward")
              .foregroundStyle(normalFillColor)
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
