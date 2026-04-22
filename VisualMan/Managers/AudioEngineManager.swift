//
//  AudioEngineManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import AVFoundation
import Synchronization
import Dependencies
import Accelerate
import os

nonisolated let audioLogger = Logger(subsystem: "com.VisualMan", category: "AudioEngineManager")

@Observable
@MainActor
final class AudioEngineManager {
  enum PlaybackState {
    case idle
    case playing
    case paused
    case seeking
    case completed
  }
  
  enum Constants {
    static let pauseDecayFactor: Float = 0.88
    static let pauseDecayThreshold: Float = 0.001
  }
  
  var audioLevels: [1024 of Float] = .init(repeating: 0.0)
  var visualizerBars: [32 of Float] = .init(repeating: 0.0)
  var waveform: [1024 of Float] = .init(repeating: 0.0)
  var playbackState: PlaybackState = .idle
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 0
  var isInitialized = false
  var failedToInitialize = false
  var initializationError: VMError?
  var currentAudioSourceURL: URL?
  
  var isPlaying: Bool { playbackState == .playing }
  
  @ObservationIgnored @Dependency(\.uuid) var uuid
  
  @ObservationIgnored private(set) var engine: AVAudioEngine?
  @ObservationIgnored private var securityScopedURL: URL?
  @ObservationIgnored var playbackContinuation: AsyncStream<Void>.Continuation?
  @ObservationIgnored var pauseDecayTask: Task<Void, Never>?
  @ObservationIgnored var pauseDecayStream: DisplayLinkStream?
  
  @ObservationIgnored var player: AVAudioPlayerNode?
  @ObservationIgnored var audioFile: AVAudioFile?
  @ObservationIgnored var displayLinkStream: DisplayLinkStream?
  @ObservationIgnored var displayLinkTask: Task<Void, Never>?
  @ObservationIgnored var lastSeekFrame: AVAudioFramePosition = 0
  @ObservationIgnored var currentPlaybackID: UUID
  @ObservationIgnored var nowPlayingTask: Task<Void, Never>?
  @ObservationIgnored var interruptionObserver: (any NSObjectProtocol)?
  @ObservationIgnored var routeChangeObserver: (any NSObjectProtocol)?
  @ObservationIgnored var configChangeObserver: (any NSObjectProtocol)?
  
  let audioTapProcessor = AudioTapProcessor()
  
  let playbackCompleted: AsyncStream<Void>
  
  init() {
    @Dependency(\.uuid) var uuid
    let initialID = uuid()
    currentPlaybackID = initialID
    
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    playbackCompleted = stream
    playbackContinuation = continuation
    do {
      try setupAudioEngine()
      isInitialized = true
    } catch {
      initializationError = VMError.unableToInitialize(underlying: error)
      isInitialized = false
      failedToInitialize = true
    }
    observeAudioSessionInterruptions()
  }
  
  isolated deinit {
    displayLinkTask?.cancel()
    pauseDecayTask?.cancel()
    nowPlayingTask?.cancel()
    playbackContinuation?.finish()
    for observer in [interruptionObserver, routeChangeObserver, configChangeObserver].compactMap({ $0 }) {
      NotificationCenter.default.removeObserver(observer)
    }
  }
  
  private func setupAudioEngine() throws {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      throw VMError.invalidSession(underlying: error)
    }
    
    engine = AVAudioEngine()
    
    player = AVAudioPlayerNode()
    
    guard let engine,
          let player else { return }
    
    _ = engine.mainMixerNode

    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: nil)
  }
  
  func play(_ source: AudioSource) async throws {
    if currentAudioSourceURL == source.getPlaybackURL() && playbackState == .playing { return }

    player?.stop()

    stopDisplayLink()
    engine?.mainMixerNode.removeTap(onBus: 0)

    audioLevels = [1024 of Float](repeating: 0.0)
    visualizerBars = [32 of Float](repeating: 0.0)
    waveform = [1024 of Float](repeating: 0.0)
    await audioTapProcessor.reset()
    lastSeekFrame = 0

    guard let url = source.getPlaybackURL() else {
      throw VMError.invalidURL
    }

    let isSecurityScoped = (source as? FileAudioSource)?.isSecurityScoped ?? false
    try play(from: url, isSecurityScoped: isSecurityScoped)
    currentAudioSourceURL = source.getPlaybackURL()
  }

  private func play(from url: URL, isSecurityScoped: Bool) throws {
    stopSecurityScopedAccess()

    let accessing = url.startAccessingSecurityScopedResource()
    if isSecurityScoped || accessing {
      securityScopedURL = url
    }
    try playAudioFromURL(url)
  }
  
  private func playAudioFromURL(_ url: URL) throws {
    guard let engine,
          let player else {
      throw VMError.nilEngineOrPlayer
    }
    
    let playbackID = uuid()
    currentPlaybackID = playbackID
    
    do {
      audioFile = try AVAudioFile(forReading: url)
      
      guard let audioFile else {
        throw VMError.failedToCreateFile
      }
      
      duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
      
      try AVAudioSession.sharedInstance().setActive(true)

      engine.prepare()

      if !engine.isRunning {
        try engine.start()
      }
      
      player.scheduleFile(audioFile, at: nil) { [weak self] in
        Task { @MainActor in
          guard let self,
                self.currentPlaybackID == playbackID else { return }
          self.handlePlaybackCompleted()
        }
      }
      
      playbackState = .playing
      startDisplayLink()
    } catch {
      playbackState = .idle
      stopDisplayLink()
      throw VMError.failedToPlay(underlying: error)
    }
    
    installAudioTap(on: engine)
    
    player.play()
  }
  
  func installAudioTap(on engine: AVAudioEngine) {
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    let tapProcessor = audioTapProcessor

    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable buffer, _ in
      guard let channelData = buffer.floatChannelData else { return }
      let frameLength = Int(buffer.frameLength)
      let channelCount = Int(buffer.format.channelCount)
      let sampleRate = Float(buffer.format.sampleRate)
      tapProcessor.processSamples(
        channels: channelData,
        channelCount: channelCount,
        frameCount: frameLength,
        sampleRate: sampleRate
      )
    }
  }
  
  func stopSecurityScopedAccess() {
    if let url = securityScopedURL {
      url.stopAccessingSecurityScopedResource()
      securityScopedURL = nil
    }
  }
  
}
