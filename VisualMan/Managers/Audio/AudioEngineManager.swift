//
//  AudioEngineManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import AVFoundation
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
    static let pauseDecayThreshold: Float = 0.001
    static let completionTolerance: TimeInterval = 1.0
  }
  
  var audioLevels: [1024 of Float] = .init(repeating: 0.0)
  var visualizerBars: [32 of Float] = .init(repeating: 0.0)
  var waveform: [1024 of Float] = .init(repeating: 0.0)
  var playbackState: PlaybackState = .idle
  var currentTime: TimeInterval = 0 {
    didSet {
      let hasPosition = currentTime > 0
      if hasPosition != hasPlaybackPosition { hasPlaybackPosition = hasPosition }
    }
  }
  private(set) var hasPlaybackPosition = false
  var duration: TimeInterval = 0
  var failedToInitialize = false
  var initializationError: VMError?
  var currentAudioSourceURL: URL?
  
  var isPlaying: Bool { playbackState == .playing }
  
  @ObservationIgnored @Dependency(\.uuid) var uuid
  @ObservationIgnored @Dependency(HapticsManager.self) var hapticsManager
  @ObservationIgnored @Dependency(AccessibilityManager.self) var accessibilityManager
  @ObservationIgnored var audioConditioner = VisualizerAudioConditioner()
  
  @ObservationIgnored private(set) var engine: AVAudioEngine?
  @ObservationIgnored private var securityScopedURL: URL?
  @ObservationIgnored var playbackCompletionContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
  @ObservationIgnored var pauseDecayTask: Task<Void, Never>?
  @ObservationIgnored var pauseDecayStream: DisplayLinkStream?
  
  @ObservationIgnored var player: AVAudioPlayerNode?
  @ObservationIgnored var audioFile: AVAudioFile?
  @ObservationIgnored var displayLinkStream: DisplayLinkStream?
  @ObservationIgnored var displayLinkTask: Task<Void, Never>?
  @ObservationIgnored var lastSeekFrame: AVAudioFramePosition = 0
  @ObservationIgnored var currentPlaybackID: UUID
  @ObservationIgnored var nowPlayingTask: Task<Void, Never>?
  @ObservationIgnored var sessionDeactivationTask: Task<Void, Never>?
  @ObservationIgnored var interruptionObserver: (any NSObjectProtocol)?
  @ObservationIgnored var routeChangeObserver: (any NSObjectProtocol)?
  @ObservationIgnored var configChangeObserver: (any NSObjectProtocol)?
  @ObservationIgnored var resumesAfterInterruption = false
  
  let audioTapProcessor = AudioTapProcessor()
  let engineLock = NSRecursiveLock()
  let engineShouldRun = OSAllocatedUnfairLock(initialState: false)

  init() {
    @Dependency(\.uuid) var uuid
    let initialID = uuid()
    currentPlaybackID = initialID

    do {
      try setupAudioEngine()
    } catch {
      initializationError = VMError.unableToInitialize(underlying: error)
      failedToInitialize = true
    }
    observeAudioSessionInterruptions()
  }
  
  isolated deinit {
    sessionDeactivationTask?.cancel()
    engineLock.withLock {
      engineShouldRun.withLock { $0 = false }
      player?.stop()
      engine?.mainMixerNode.removeTap(onBus: 0)
      engine?.stop()
    }
    displayLinkStream?.stop()
    displayLinkTask?.cancel()
    pauseDecayStream?.stop()
    pauseDecayTask?.cancel()
    nowPlayingTask?.cancel()
    for continuation in playbackCompletionContinuations.values {
      continuation.finish()
    }
    stopSecurityScopedAccess()
    for observer in [interruptionObserver, routeChangeObserver, configChangeObserver].compactMap({ $0 }) {
      NotificationCenter.default.removeObserver(observer)
    }
    Task.detached(priority: .utility) {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }
  
  private func setupAudioEngine() throws {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    } catch {
      throw VMError.invalidSession(underlying: error)
    }
    
    engine = AVAudioEngine()
    
    player = AVAudioPlayerNode()
    
    guard let engine,
          let player else {
      throw VMError.nilEngineOrPlayer
    }
    
    _ = engine.mainMixerNode

    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: nil)
  }
  
  func play(_ source: AudioSource) async throws {
    if currentAudioSourceURL == source.getPlaybackURL() && playbackState == .playing { return }

    let signpostID = pointsOfInterest.makeSignpostID()
    let playState = pointsOfInterest.beginInterval("Play Song", id: signpostID,
                                                   "\(source.title ?? "Unknown", privacy: .public)")
    defer { pointsOfInterest.endInterval("Play Song", playState) }

    let playbackID = uuid()
    currentPlaybackID = playbackID
    let pendingDeactivation = sessionDeactivationTask
    sessionDeactivationTask = nil
    pendingDeactivation?.cancel()

    engineLock.withLock {
      player?.stop()
      engine?.mainMixerNode.removeTap(onBus: 0)
    }
    stopPauseDecay()
    stopDisplayLink()

    if accessibilityManager.reducesFlashing || accessibilityManager.intensity.fallSeconds > 0 {
      startPauseDecay()
    } else {
      audioLevels = [1024 of Float](repeating: 0.0)
      visualizerBars = [32 of Float](repeating: 0.0)
      waveform = [1024 of Float](repeating: 0.0)
      audioConditioner.reset()
    }
    await audioTapProcessor.reset()
    await pendingDeactivation?.value
    guard currentPlaybackID == playbackID else { return }
    lastSeekFrame = 0

    guard let url = source.getPlaybackURL() else {
      throw VMError.invalidURL
    }

    let isSecurityScoped = (source as? FileAudioSource)?.isSecurityScoped ?? false
    do {
      try await play(from: url, isSecurityScoped: isSecurityScoped, playbackID: playbackID)
    } catch is CancellationError {
      return
    }
    currentAudioSourceURL = source.getPlaybackURL()
  }

  private func play(from url: URL, isSecurityScoped: Bool, playbackID: UUID) async throws {
    stopSecurityScopedAccess()

    let accessing = url.startAccessingSecurityScopedResource()
    if isSecurityScoped || accessing {
      securityScopedURL = url
    }
    try await playAudioFromURL(url, playbackID: playbackID)
  }

  private func playAudioFromURL(_ url: URL, playbackID: UUID) async throws {
    guard let engine,
          let player else {
      throw VMError.nilEngineOrPlayer
    }

    let opened: OpenedAudioFile
    let openState = pointsOfInterest.beginInterval("Open Audio File")
    do {
      opened = try await Self.openAudioFile(at: url)
      pointsOfInterest.endInterval("Open Audio File", openState)
    } catch {
      pointsOfInterest.endInterval("Open Audio File", openState)
      guard currentPlaybackID == playbackID else { throw CancellationError() }
      playbackState = .idle
      throw VMError.failedToPlay(underlying: error)
    }
    
    guard currentPlaybackID == playbackID else { throw CancellationError() }

    do {
      audioFile = opened.file

      guard let audioFile else {
        throw VMError.failedToCreateFile
      }

      duration = opened.duration

      let sessionState = pointsOfInterest.beginInterval("Activate Audio Session")
      do {
        try await activateAudioSession()
        pointsOfInterest.endInterval("Activate Audio Session", sessionState)
      } catch {
        pointsOfInterest.endInterval("Activate Audio Session", sessionState)
        throw error
      }

      try await startEngine(engine)

      guard currentPlaybackID == playbackID else { throw CancellationError() }

      try engineLock.withLock {
        guard engine.isRunning else { throw VMError.failedToPlay(underlying: nil) }
        schedule(audioFile, on: player, playbackID: playbackID)
        installAudioTap(on: engine)
        try player.playCatchingExceptions()
      }
      hapticsManager.loadTrack(at: url)

      playbackState = .playing
      startDisplayLink()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      playbackState = .idle
      stopDisplayLink()
      throw VMError.failedToPlay(underlying: error)
    }
  }
  
  nonisolated struct OpenedAudioFile {
    let file: AVAudioFile
    let duration: TimeInterval
  }

  @concurrent
  nonisolated private static func openAudioFile(at url: URL) async throws -> sending OpenedAudioFile {
    let file = try AVAudioFile(forReading: url)
    let duration = Double(file.length) / file.fileFormat.sampleRate
    return OpenedAudioFile(file: file, duration: duration)
  }

  private func schedule(_ audioFile: AVAudioFile, on player: AVAudioPlayerNode, playbackID: UUID) {
    player.scheduleFile(audioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      Task { @MainActor in
        self?.handleScheduledAudioFinished(playbackID: playbackID)
      }
    }
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
