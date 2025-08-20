//
//  MusicPlayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/14/25.
//

import SwiftUI
import MediaPlayer
import Combine

struct MusicPlayerView: View {
  @Environment(AudioPlaylistManager.self) private var playlistManager
  
  @State private var audioManager = AudioEngineManager.shared
  @State private var currentVisualizer = Visualizers.bars
  @State private var isTapped: Bool = false
  @State private var failedPlaying: Bool = false
  @State private var playingError: Error?
  @State private var scrollToEnd = false
  @State private var textSize: CGSize = .zero
  @State private var containerSize: CGSize = .zero
  @State private var scrollAnimationKey = UUID()
  @State private var playbackCompletionCancellable: AnyCancellable?
  @State private var nowPlayingTimer: Timer?
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
  
  private var hasNext: Bool {
    playlistManager.hasNext
  }
  
  private var hasPrevious: Bool {
    playlistManager.hasPrevious
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
            skipBackwards()
          } label: {
            Image(systemName: "backward")
              .foregroundStyle(normalFillColor)
          }
          .padding()
          
          Spacer()
          
          Button {
            if audioManager.isPlaying {
              audioManager.pause()
            } else if audioManager.currentTime > 0 && audioManager.currentTime < audioManager.duration {
              audioManager.resume()
            } else {
              playCurrentSong()
            }
          } label: {
            Image(systemName: audioManager.isPlaying ? "pause" : "play")
              .foregroundStyle(normalFillColor)
          }
          .padding()
          
          Spacer()
          
          Button {
            skipForwards()
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
    .onAppear {
      isShowingTabPlayer = false
      
      playlistManager.setPlaylist(_audioSources, startingIndex: _startingIndex)
      
      setupLockScreenControls()
      
      playbackCompletionCancellable = audioManager.playbackCompleted
        .receive(on: DispatchQueue.main)
        .sink { _ in
          onSongCompleted()
        }
      
      do {
        guard let currentSource = playlistManager.currentAudioSource else {
          throw NSError(domain: "MusicPlayerView", code: 0, userInfo: [NSLocalizedDescriptionKey: "No audio source available"])
        }
        try audioManager.play(currentSource)
        updateNowPlayingInfo()
        
        audioManager.startNowPlayingTimer {
          self.updateNowPlayingInfo()
        }
      } catch {
        playingError = error
        failedPlaying.toggle()
      }
    }
    .onDisappear {
      isShowingTabPlayer = true
      cleanup()
    }
    .onTapGesture {
      withAnimation(.easeInOut) {
        isTapped.toggle()
      }
    }
    .alert("Failed to play song: \(playingError?.localizedDescription ?? "Unknown playing error")", isPresented: $failedPlaying) {
      Button("Okay", role: .cancel) {
        failedPlaying = false
        playingError = nil
      }
    }
    .alert("Failed to initialize audioEngine: \(audioManager.initializationError?.localizedDescription ?? "Unknown initialization error")", isPresented: $audioManager.failedToInitialize) {
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
  
  private func playCurrentSong() {
    guard let source = currentAudioSource else { return }
    
    do {
      try audioManager.play(source)
      updateNowPlayingInfo()
    } catch {
      playingError = error
      failedPlaying = true
    }
  }
  
  private func skipBackwards() {
    if audioManager.currentTime >= 3 {
      audioManager.seek(to: 0)
      return
    } else if playlistManager.hasPrevious {
      audioManager.stop()
      playlistManager.moveToPrevious()
      playCurrentSong()
    } else if playlistManager.currentIndex == 0 {
      audioManager.seek(to: 0)
    }
  }
  
  private func skipForwards() {
    guard hasNext else { return }
    audioManager.stop()
    playlistManager.moveToNext()
    playCurrentSong()
  }
  
  private func onSongCompleted() {
    audioManager.stop()
    
    if hasNext {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        playlistManager.moveToNext()
        playCurrentSong()
      }
    } else {
      playlistManager.moveToIndex(0)
    }
  }
  
  private func setupLockScreenControls() {
    let lockScreen = LockScreenControlManager.shared
    
    lockScreen.onPlayPause = {
      if audioManager.isPlaying {
        audioManager.pause()
      } else if audioManager.currentTime > 0 && audioManager.currentTime < audioManager.duration {
        audioManager.resume()
      } else {
        playCurrentSong()
      }
      self.updateNowPlayingInfo()
    }
    
    lockScreen.onNext = {
      skipForwards()
    }
    
    lockScreen.onPrevious = {
      skipBackwards()
    }
  }
  
  private func updateNowPlayingInfo() {
    guard let source = currentAudioSource else { return }
    
    LockScreenControlManager.shared.updateNowPlayingInfo(
      title: source.title,
      artist: source.artist,
      albumArt: source.albumArt,
      duration: audioManager.duration,
      currentTime: audioManager.currentTime,
      isPlaying: audioManager.isPlaying
    )
  }
  
  private func startNowPlayingTimer() {
    stopNowPlayingTimer()
    nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
      Task { @MainActor in
        updateNowPlayingInfo()
      }
    }
  }
  
  private func stopNowPlayingTimer() {
    nowPlayingTimer?.invalidate()
    nowPlayingTimer = nil
  }
  
  private func cleanup() {
    playbackCompletionCancellable?.cancel()
    playbackCompletionCancellable = nil
    stopNowPlayingTimer()
  }
  
  @ViewBuilder
  private func currentShader(currentVisualizer: Visualizers, visualizerBars: [Float], audioLevels: [Float], albumArt: UIImage?) -> some View {
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
