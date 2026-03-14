//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer

struct MusicPlayerView: View {
  @State private var viewModel = MusicPlayerViewModel()
  @State private var currentVisualizer = Visualizers.bars
  @State private var isTapped: Bool = false
  
  @Environment(AudioEngineManager.self) private var audioManager
  @Environment(AudioPlaylistManager.self) private var playlistManager
  
  private let sliderColor: Color = .white
  
  private var normalFillColor: Color {
    sliderColor.opacity(0.5)
  }
  private var emptyColor: Color {
    sliderColor.opacity(0.3)
  }
  
  private var currentAudioSource: (any AudioSource)? {
    playlistManager.currentAudioSource
  }
  
  private enum Visualizers: String, CaseIterable {
    case bars = "Bars"
    case threeD = "3D Bars"
    case album = "Album Art Waves"
    case julia = "Julia Set"
    case fireworks = "Fireworks"
    case interference = "Interference Pattern"
    case voronoi = "Voronoi Diagram"
  }
  
  init(_ audioSources: [any AudioSource], startingIndex: Int) {
    _audioSources = audioSources
    _startingIndex = startingIndex
  }
  
  init(fileAudioSource: FileAudioSource) {
    let sources = [fileAudioSource]
    _audioSources = sources
    _startingIndex = 0
  }
  
  private let _audioSources: [any AudioSource]
  private let _startingIndex: Int
  
  var body: some View {
    @Bindable var audioManager = audioManager
    
    ZStack {
      currentShader(currentVisualizer: currentVisualizer,
                    visualizerBars: audioManager.visualizerBars,
                    audioLevels: audioManager.audioLevels,
                    albumArt: currentAudioSource?.albumArt)
      .ignoresSafeArea()
      .onTapGesture {
        withAnimation(.easeInOut) {
          isTapped.toggle()
        }
      }
      VStack {
        Spacer()
        if let current = currentAudioSource {
          MarqueeTextView(
            "\(current.title ?? "Unknown") • \(current.artist ?? "Unknown")",
            resetID: playlistManager.currentIndex
          )
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundStyle(.white)
          .frame(height: 40)
        }
        ProgressSliderView(value: $audioManager.currentTime,
                           inRange: TimeInterval.zero...max(audioManager.duration, 0.1),
                           activeFillColor: sliderColor,
                           fillColor: normalFillColor,
                           emptyColor: emptyColor,
                           height: 8
        ) { isDragging in
          if !isDragging {
            audioManager.seek(to: audioManager.currentTime)
          }
        }
        .frame(height: 60)
        .padding()
        HStack {
          Button {
            viewModel.skipBackwards()
          } label: {
            Image(systemName: "backward")
              .foregroundStyle(normalFillColor)
          }
          .accessibilityLabel("Previous")
          .padding()
          
          Spacer()
          
          Button {
            viewModel.togglePlayback()
          } label: {
            Image(systemName: audioManager.isPlaying ? "pause" : "play")
              .foregroundStyle(normalFillColor)
          }
          .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
          .padding()
          
          Spacer()
          
          Button {
            viewModel.skipForwards()
          } label: {
            Image(systemName: "forward")
              .foregroundStyle(normalFillColor)
          }
          .accessibilityLabel("Next")
          .padding()
        }
        .contentShape(Rectangle())
        .padding()
      }
      .background(
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0.4),
            .init(color: .black.opacity(0.7), location: 1.0)
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(.easeInOut) {
          isTapped.toggle()
        }
      }
      .zIndex(1)
      .opacity(isTapped ? 0 : 1)
      .allowsHitTesting(!isTapped)
    }
    .toolbar(.hidden, for: .tabBar)
    .onAppear {
      viewModel.start(playlistManager: playlistManager, audioSources: _audioSources, startingIndex: _startingIndex)
    }
    .onDisappear {
      viewModel.cleanup()
    }
    .alert(viewModel.playingError?.errorDescription ?? "An unknown error occurred during playback.", isPresented: $viewModel.failedPlaying) {
      Button("Okay", role: .cancel) {
        viewModel.failedPlaying = false
        viewModel.playingError = nil
      }
    }
    .alert(audioManager.initializationError?.errorDescription ?? "An unknown error occurred during initialization.", isPresented: $audioManager.failedToInitialize) {
      Button("Okay", role: .cancel) {
        audioManager.failedToInitialize = false
        audioManager.initializationError = nil
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          ForEach(Visualizers.allCases, id: \.self) { type in
            Button {
              currentVisualizer = type
            } label: {
              if type == currentVisualizer {
                Label(type.rawValue, systemImage: "checkmark")
              } else {
                Text(type.rawValue)
              }
            }
          }
        } label: {
          Text(currentVisualizer.rawValue)
        }
      }
    }
  }
  
  @ViewBuilder
  private func currentShader(currentVisualizer: Visualizers, visualizerBars: [32 of Float], audioLevels: [1024 of Float], albumArt: UIImage?) -> some View {
    switch currentVisualizer {
    case .bars:
      BarsVisualizerView(visualizerBars: visualizerBars)
    case .threeD:
      ThreeDBarsVisualizerView(visualizerBars: visualizerBars)
    case .album:
      AlbumArtWaveVisualizerView(audioLevels: audioLevels, albumArt: albumArt)
    case .julia:
      JuliaVisualizerView(audioLevels: audioLevels)
    case .fireworks:
      FireworksVisualizerView(audioLevels: audioLevels)
    case .interference:
      InterferenceVisualizerView(audioLevels: audioLevels)
    case .voronoi:
      VoronoiVisualizerView(audioLevels: audioLevels)
    }
  }
}
