//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer

struct MusicPlayerView: View {
  @Environment(AudioPlaylistManager.self) private var playlistManager
  
  @State private var audioManager = AudioEngineManager.shared
  @State private var viewModel = MusicPlayerViewModel()
  @State private var currentVisualizer = Visualizers.bars
  @State private var isTapped: Bool = false
  @State private var scrollToEnd = false
  @State private var textSize: CGSize = .zero
  @State private var containerSize: CGSize = .zero
  @State private var scrollAnimationKey = UUID()
  @State private var isShowingTabPlayer: Bool = true
  
  private var sliderColor: Color = .white
  
  private var shouldScroll: Bool {
    textSize.width > containerSize.width
  }
  
  private var scrollDuration: Double {
    Double(textSize.width) / 20.0
  }
  
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
    ZStack {
      currentShader(currentVisualizer: currentVisualizer,
                    visualizerBars: audioManager.visualizerBars,
                    audioLevels: audioManager.audioLevels,
                    albumArt: currentAudioSource?.albumArt)
      .ignoresSafeArea()
      VStack {
        Spacer()
        if let current = currentAudioSource {
          GeometryReader { g in
            ScrollViewReader { _ in
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: shouldScroll ? 100 : 0) {
                  ForEach(0..<(shouldScroll ? 3 : 1), id: \.self) { _ in
                    Text("\(current.title ?? "Unknown") • \(current.artist ?? "Unknown")")
                      .font(.title2)
                      .fontWeight(.semibold)
                      .foregroundColor(.white)
                      .lineLimit(1)
                      .fixedSize()
                      .background(
                        GeometryReader { textGeometry in
                          Color.clear
                            .onAppear {
                              let newSize = textGeometry.size
                              if newSize != textSize {
                                textSize = newSize
                              }
                            }
                        }
                      )
                  }
                }
                .id("\(playlistManager.currentIndex)-\(scrollAnimationKey)")
                .padding(.horizontal)
                .offset(x: shouldScroll ? (scrollToEnd ? -textSize.width - 100 : 0) : 0)
                .animation(scrollToEnd ? .linear(duration: scrollDuration).repeatForever(autoreverses: false) : .none, value: scrollToEnd)
              }
              .disabled(true)
              .onAppear {
                containerSize = g.size
              }
              .onChange(of: textSize) { oldSize, newSize in
                if oldSize == .zero && newSize.width > containerSize.width && !scrollToEnd {
                  DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    scrollToEnd = true
                  }
                }
              }
              .onChange(of: playlistManager.currentIndex) { _, _ in
                scrollToEnd = false
                textSize = .zero
                scrollAnimationKey = UUID()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  scrollAnimationKey = UUID()
                }
              }
              .onChange(of: scrollAnimationKey) { _, _ in
                if textSize.width > containerSize.width {
                  DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    scrollToEnd = true
                  }
                }
              }
            }
          }
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
            viewModel.skipBackwards(playlistManager: playlistManager)
          } label: {
            Image(systemName: "backward")
              .foregroundStyle(normalFillColor)
          }
          .padding()
          
          Spacer()
          
          Button {
            viewModel.togglePlayback(playlistManager: playlistManager)
          } label: {
            Image(systemName: audioManager.isPlaying ? "pause" : "play")
              .foregroundStyle(normalFillColor)
          }
          .padding()
          
          Spacer()
          
          Button {
            viewModel.skipForwards(playlistManager: playlistManager)
          } label: {
            Image(systemName: "forward")
              .foregroundStyle(normalFillColor)
          }
          .padding()
        }
        .padding()
      }
      .zIndex(1)
      .opacity(isTapped ? 0 : 1)
    }
    .toolbar(.hidden, for: .tabBar)
    .onAppear {
      isShowingTabPlayer = false
      viewModel.start(playlistManager: playlistManager, audioSources: _audioSources, startingIndex: _startingIndex)
    }
    .onDisappear {
      isShowingTabPlayer = true
      viewModel.cleanup()
    }
    .onTapGesture {
      withAnimation(.easeInOut) {
        isTapped.toggle()
      }
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
  private func currentShader(currentVisualizer: Visualizers, visualizerBars: [32 of Float], audioLevels: [512 of Float], albumArt: UIImage?) -> some View {
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
