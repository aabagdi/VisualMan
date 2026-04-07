//
//  AudioEngineManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import AVFoundation
import Synchronization
import Dependencies

@Observable
@MainActor
final class AudioEngineManager {
  var audioLevels = [1024 of Float](repeating: 0.0)
  var visualizerBars = [32 of Float](repeating: 0.0)
  var isPlaying = false
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 0
  var isInitialized = false
  var failedToInitialize = false
  var initializationError: VMError?
  var currentAudioSourceURL: URL?
  
  @ObservationIgnored @Dependency(\.uuid) var uuid
  
  @ObservationIgnored private var engine: AVAudioEngine?
  @ObservationIgnored private var player: AVAudioPlayerNode?
  @ObservationIgnored private var audioFile: AVAudioFile?
  @ObservationIgnored private var displayLinkStream: DisplayLinkStream?
  @ObservationIgnored private var displayLinkTask: Task<Void, Never>?
  @ObservationIgnored private var securityScopedURL: URL?
  @ObservationIgnored private var lastSeekFrame: AVAudioFramePosition = 0
  @ObservationIgnored private var isSeeking: Bool = false
  @ObservationIgnored private var hasHandledCompletion = false
  @ObservationIgnored private var currentPlaybackID: UUID
  @ObservationIgnored private var nowPlayingTask: Task<Void, Never>?
  @ObservationIgnored private var playbackContinuation: AsyncStream<Void>.Continuation?
  
  private let audioTapProcessor = AudioTapProcessor()
  
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
      initializationError = VMError.unableToInitialize
      isInitialized = false
      failedToInitialize = true
    }
    observeAudioSessionInterruptions()
  }
  
  deinit {
    playbackContinuation?.finish()
  }
  
  private func setupAudioEngine() throws {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      throw VMError.invalidSession
    }
    
    engine = AVAudioEngine()
    
    player = AVAudioPlayerNode()
    
    guard let engine,
          let player else { return }
    
    _ = engine.mainMixerNode
    
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    
    engine.stop()
    
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }
  
  func play(_ source: AudioSource) async throws {
    if currentAudioSourceURL == source.getPlaybackURL() && isPlaying { return }
    
    player?.stop()
    
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
    
    hasHandledCompletion = false
    
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
      
      isPlaying = true
      startDisplayLink()
    } catch {
      isPlaying = false
      stopDisplayLink()
      throw VMError.failedToPlay
    }
    
    installAudioTap(on: engine)
    
    player.play()
  }
  
  private func installAudioTap(on engine: AVAudioEngine) {
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    let tapProcessor = audioTapProcessor
    
    let sampleRate = Float(format.sampleRate)
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable buffer, _ in
      guard let channelData = buffer.floatChannelData?[0] else { return }
      let frameLength = Int(buffer.frameLength)
      let samples = UnsafeBufferPointer(start: channelData, count: frameLength)
      tapProcessor.processSamples(samples, sampleRate: sampleRate)
    }
    
    audioTapProcessor.startForwarding { [weak self] result in
      self?.audioLevels = result.audioLevels
      self?.visualizerBars = result.visualizerBars
    }
  }
  
  private func stopSecurityScopedAccess() {
    if let url = securityScopedURL {
      url.stopAccessingSecurityScopedResource()
      securityScopedURL = nil
    }
  }
  
  private func handlePlaybackCompleted() {
    guard !hasHandledCompletion else { return }
    hasHandledCompletion = true
    
    isPlaying = false
    currentTime = duration
    stopDisplayLink()
    playbackContinuation?.yield()
  }
  
  func pause() {
    player?.pause()
    isPlaying = false
    stopDisplayLink()
  }
  
  func resume() {
    player?.play()
    isPlaying = true
    startDisplayLink()
  }

  func stopForTransition() {
    currentPlaybackID = uuid()
    player?.stop()
    audioTapProcessor.stopForwarding()
    engine?.mainMixerNode.removeTap(onBus: 0)
    isPlaying = false
    currentTime = 0
    stopDisplayLink()
    stopSecurityScopedAccess()
    if !isSeeking {
      lastSeekFrame = 0
    }
    hasHandledCompletion = false
    currentAudioSourceURL = nil
  }
  
  func stop() {
    stopForTransition()
    engine?.stop()
    stopNowPlayingTimer()
  }
  
  private func observeAudioSessionInterruptions() {
    NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] notification in
      guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
      let options: AVAudioSession.InterruptionOptions? = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt)
        .map { AVAudioSession.InterruptionOptions(rawValue: $0) }
      Task { @MainActor in
        self?.handleInterruption(type: type, options: options)
      }
    }
  }
  
  private func handleInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions?) {
    switch type {
    case .began:
      if isPlaying {
        player?.pause()
        isPlaying = false
        stopDisplayLink()
      }
    case .ended:
      if let options, options.contains(.shouldResume) {
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
        startDisplayLink()
      }
    @unknown default:
      break
    }
  }
  
  func seek(to time: TimeInterval) {
    guard let player,
          let audioFile else { return }
    
    isSeeking = true
    
    currentPlaybackID = uuid()
    hasHandledCompletion = false
    
    let sampleRate = audioFile.fileFormat.sampleRate
    let newFrame = AVAudioFramePosition(time * sampleRate)
    
    let clampedFrame = max(0, min(newFrame, audioFile.length))
    
    lastSeekFrame = clampedFrame
    
    player.stop()
    
    if clampedFrame < audioFile.length {
      let playbackID = currentPlaybackID
      player.scheduleSegment(
        audioFile,
        startingFrame: clampedFrame,
        frameCount: AVAudioFrameCount(audioFile.length - clampedFrame),
        at: nil
      ) { [weak self] in
        Task { @MainActor in
          guard let self,
                self.currentPlaybackID == playbackID else { return }
          self.handlePlaybackCompleted()
        }
      }
      
      if isPlaying {
        player.play()
      }
      
      currentTime = time
    } else {
      currentTime = duration
      isSeeking = false
      handlePlaybackCompleted()
      return
    }
    
    isSeeking = false
  }
  
}

extension AudioEngineManager {
  func startNowPlayingTimer(updateHandler: @escaping @MainActor () -> Void) {
    stopNowPlayingTimer()
    nowPlayingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, self != nil else { break }
        updateHandler()
      }
    }
  }
  
  func stopNowPlayingTimer() {
    nowPlayingTask?.cancel()
    nowPlayingTask = nil
  }
  
  func startDisplayLink() {
    stopDisplayLink()
    let stream = DisplayLinkStream()
    displayLinkStream = stream
    displayLinkTask = Task { [weak self] in
      for await _ in stream.frames {
        guard !Task.isCancelled else { break }
        self?.updateTime()
      }
    }
  }
  
  func stopDisplayLink() {
    displayLinkTask?.cancel()
    displayLinkTask = nil
    displayLinkStream?.stop()
    displayLinkStream = nil
  }
  
  private func updateTime() {
    guard let player,
          let audioFile,
          player.isPlaying else { return }
    
    if let nodeTime = player.lastRenderTime,
       let playerTime = player.playerTime(forNodeTime: nodeTime) {
      let sampleTime = playerTime.sampleTime
      
      guard sampleTime >= 0 else { return }
      
      let playerSeconds = Double(sampleTime) / playerTime.sampleRate
      let seekSeconds = Double(lastSeekFrame) / audioFile.fileFormat.sampleRate
      let newTime = seekSeconds + playerSeconds
      
      if newTime >= 0 && newTime <= duration {
        currentTime = newTime
      }
      
      if currentTime >= duration - 0.05 && !isSeeking && !hasHandledCompletion {
        handlePlaybackCompleted()
      }
    }
  }
}
