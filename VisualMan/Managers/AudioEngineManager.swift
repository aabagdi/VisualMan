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
  
  private enum Constants {
    static let pauseDecayFactor: Float = 0.88
    static let pauseDecayThreshold: Float = 0.001
  }
  
  var audioLevels: [1024 of Float] = .init(repeating: 0.0)
  var visualizerBars: [32 of Float] = .init(repeating: 0.0)
  var playbackState: PlaybackState = .idle
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 0
  var isInitialized = false
  var failedToInitialize = false
  var initializationError: VMError?
  var currentAudioSourceURL: URL?
  
  var isPlaying: Bool { playbackState == .playing }
  
  @ObservationIgnored @Dependency(\.uuid) var uuid
  
  @ObservationIgnored private var engine: AVAudioEngine?
  @ObservationIgnored private var securityScopedURL: URL?
  @ObservationIgnored private var playbackContinuation: AsyncStream<Void>.Continuation?
  @ObservationIgnored private var pauseDecayTask: Task<Void, Never>?
  @ObservationIgnored private var pauseDecayStream: DisplayLinkStream?
  
  @ObservationIgnored var player: AVAudioPlayerNode?
  @ObservationIgnored var audioFile: AVAudioFile?
  @ObservationIgnored var displayLinkStream: DisplayLinkStream?
  @ObservationIgnored var displayLinkTask: Task<Void, Never>?
  @ObservationIgnored var lastSeekFrame: AVAudioFramePosition = 0
  @ObservationIgnored var currentPlaybackID: UUID
  @ObservationIgnored var nowPlayingTask: Task<Void, Never>?
  
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
    
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }
  
  func play(_ source: AudioSource) async throws {
    if currentAudioSourceURL == source.getPlaybackURL() && playbackState == .playing { return }
    
    player?.stop()
    
    stopDisplayLink()
    engine?.mainMixerNode.removeTap(onBus: 0)
    
    audioLevels = [1024 of Float](repeating: 0.0)
    visualizerBars = [32 of Float](repeating: 0.0)
    await audioTapProcessor.reset()
    lastSeekFrame = 0
    
    guard let url = source.getPlaybackURL() else {
      throw VMError.invalidURL
    }
    
    try play(from: url)
    currentAudioSourceURL = source.getPlaybackURL()
  }
  
  private func play(from url: URL) throws {
    stopSecurityScopedAccess()
    
    let accessing = url.startAccessingSecurityScopedResource()
    
    if accessing {
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
  
  private func installAudioTap(on engine: AVAudioEngine) {
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    let tapProcessor = audioTapProcessor
    
    let sampleRate = Float(format.sampleRate)
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable buffer, _ in
      guard let channelData = buffer.floatChannelData else { return }
      let frameLength = Int(buffer.frameLength)
      let channelCount = Int(buffer.format.channelCount)
      tapProcessor.processSamples(
        channels: channelData,
        channelCount: channelCount,
        frameCount: frameLength,
        sampleRate: sampleRate
      )
    }
  }
  
  func startPauseDecay() {
    stopPauseDecay()
    let stream = DisplayLinkStream()
    pauseDecayStream = stream
    pauseDecayTask = Task { [weak self] in
      for await _ in stream.frames {
        guard !Task.isCancelled else { break }
        guard let self else { break }
        
        var decayFactor = Constants.pauseDecayFactor
        let threshold = Constants.pauseDecayThreshold
        
        var barMax: Float = 0
        self.visualizerBars.withUnsafeElementPointer { ptr in
          vDSP_vsmul(ptr, 1, &decayFactor, ptr, 1, 32)
          vDSP_maxv(ptr, 1, &barMax, 32)
        }
        
        var levelMax: Float = 0
        self.audioLevels.withUnsafeElementPointer { ptr in
          vDSP_vsmul(ptr, 1, &decayFactor, ptr, 1, 1024)
          vDSP_maxv(ptr, 1, &levelMax, 1024)
        }
        
        if barMax < threshold && levelMax < threshold {
          self.visualizerBars = [32 of Float](repeating: 0)
          self.audioLevels = [1024 of Float](repeating: 0)
          break
        }
      }
    }
  }
  
  func stopPauseDecay() {
    pauseDecayTask?.cancel()
    pauseDecayTask = nil
    pauseDecayStream?.stop()
    pauseDecayStream = nil
  }
  
  private func stopSecurityScopedAccess() {
    if let url = securityScopedURL {
      url.stopAccessingSecurityScopedResource()
      securityScopedURL = nil
    }
  }
  
  func handlePlaybackCompleted() {
    guard playbackState != .completed else { return }
    playbackState = .completed
    
    currentTime = duration
    stopDisplayLink()
    playbackContinuation?.yield()
  }
  
  func pause() {
    player?.pause()
    playbackState = .paused
    stopDisplayLink()
    startPauseDecay()
  }
  
  func resume() {
    stopPauseDecay()
    player?.play()
    playbackState = .playing
    startDisplayLink()
  }
  
  func stopForTransition() {
    let wasSeeking = playbackState == .seeking
    currentPlaybackID = uuid()
    player?.stop()
    stopPauseDecay()
    engine?.mainMixerNode.removeTap(onBus: 0)
    playbackState = .idle
    currentTime = 0
    stopDisplayLink()
    stopSecurityScopedAccess()
    if !wasSeeking {
      lastSeekFrame = 0
    }
    currentAudioSourceURL = nil
  }
  
  func stop() {
    stopForTransition()
    engine?.stop()
    stopNowPlayingTimer()
  }
}
