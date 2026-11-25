//
//  AudioEngineManager+Timers.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import AVFoundation
import Accelerate
import Dependencies
import os

extension AudioEngineManager {
  func playbackCompletions() -> AsyncStream<Void> {
    let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let id = uuid()
    playbackCompletionContinuations[id] = continuation
    continuation.onTermination = { [weak self] _ in
      Task { @MainActor in
        self?.playbackCompletionContinuations[id] = nil
      }
    }
    return stream
  }

  func handlePlaybackCompleted() {
    guard playbackState != .completed else { return }
    playbackState = .completed

    currentTime = duration
    stopDisplayLink()
    for continuation in playbackCompletionContinuations.values {
      continuation.yield()
    }
  }

  func pause() {
    resumesAfterInterruption = false
    engineLock.withLock {
      engineShouldRun.withLock { $0 = false }
      player?.pause()
      engine?.pause()
    }
    playbackState = .paused
    stopDisplayLink()
    startPauseDecay()
  }

  func resume() async {
    if let engine, !engine.isRunning {
      let stateBeforeStart = playbackState
      do {
        try await startEngine(engine)
      } catch {
        do {
          try await activateAudioSession()
          try await startEngine(engine)
        } catch {
          audioLogger.error("Failed to restart audio engine on resume: \(error.localizedDescription)")
        }
      }
      guard playbackState == stateBeforeStart else { return }
    }
    guard startPlayerIfEngineRunning() else { return }
    stopPauseDecay()
    playbackState = .playing
    startDisplayLink()
  }

  @discardableResult
  func startPlayerIfEngineRunning() -> Bool {
    engineLock.withLock {
      guard let engine, let player, engine.isRunning else { return false }
      do {
        try player.playCatchingExceptions()
        return true
      } catch {
        audioLogger.error("Player failed to start: \(error.localizedDescription)")
        return false
      }
    }
  }

  func startEngine(_ engine: AVAudioEngine) async throws {
    engineShouldRun.withLock { $0 = true }
    try await Self.startEngine(engine, lock: engineLock, shouldRun: engineShouldRun)
  }

  @concurrent
  nonisolated private static func startEngine(_ engine: AVAudioEngine,
                                              lock: NSRecursiveLock,
                                              shouldRun: OSAllocatedUnfairLock<Bool>) async throws {
    try lock.withLock {
      guard shouldRun.withLock({ $0 }) else { return }
      try pointsOfInterest.withIntervalSignpost("Start Audio Engine") {
        engine.prepare()
        if !engine.isRunning {
          try engine.start()
        }
      }
    }
  }

  func stopForTransition() {
    let wasSeeking = playbackState == .seeking
    currentPlaybackID = uuid()
    engineLock.withLock {
      player?.stop()
      engine?.mainMixerNode.removeTap(onBus: 0)
    }
    stopPauseDecay()
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
    engineLock.withLock {
      engineShouldRun.withLock { $0 = false }
      engine?.stop()
    }
    stopNowPlayingTimer()
    sessionDeactivationTask?.cancel()
    sessionDeactivationTask = Task { [weak self] in
      guard !Task.isCancelled else { return }
      do {
        try await self?.deactivateAudioSession()
      } catch {
        audioLogger.error("Failed to deactivate audio session: \(error.localizedDescription)")
      }
    }
  }

  func startNowPlayingTimer(updateHandler: @escaping @MainActor () -> Void) {
    stopNowPlayingTimer()
    @Dependency(\.continuousClock) var clock
    nowPlayingTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await clock.sleep(for: .seconds(1))
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
    displayLinkTask = Task { @MainActor [weak self] in
      for await _ in stream.frames {
        guard !Task.isCancelled, let self else { break }
        self.updateTime()
        await self.audioTapProcessor.tick { result in
          var levels = result.audioLevels
          var bars = result.visualizerBars
          var waveform = result.waveform
          self.audioConditioner.condition(
            levels: &levels,
            bars: &bars,
            waveform: &waveform,
            intensity: self.accessibilityManager.intensity,
            limitsFlashing: self.accessibilityManager.reducesFlashing
          )
          self.audioLevels = levels
          self.visualizerBars = bars
          self.waveform = waveform
        }
      }
    }
  }
  
  func stopDisplayLink() {
    displayLinkTask?.cancel()
    displayLinkTask = nil
    displayLinkStream?.stop()
    displayLinkStream = nil
    hapticsManager.halt()
  }
  
  private func updateTime() {
    guard let anchor = renderedPlaybackAnchor() else { return }
    let newTime = anchor.position

    if newTime >= 0 && newTime <= duration {
      currentTime = newTime
    }

    if currentTime >= duration - 0.05 && playbackState == .playing {
      handlePlaybackCompleted()
    } else if playbackState == .playing {
      hapticsManager.advance(to: anchor.position, hostTime: anchor.hostTime)
    }
  }

  func renderedPlaybackPosition() -> TimeInterval? {
    renderedPlaybackAnchor()?.position
  }

  func renderedPlaybackAnchor() -> (position: TimeInterval, hostTime: UInt64)? {
    guard let player,
          let audioFile,
          player.isPlaying,
          let nodeTime = player.lastRenderTime,
          let playerTime = player.playerTime(forNodeTime: nodeTime),
          playerTime.sampleTime >= 0 else { return nil }

    let playerSeconds = Double(playerTime.sampleTime) / playerTime.sampleRate
    let seekSeconds = Double(lastSeekFrame) / audioFile.fileFormat.sampleRate
    let hostTime = nodeTime.isHostTimeValid ? nodeTime.hostTime : mach_absolute_time()
    return (seekSeconds + playerSeconds, hostTime)
  }

  func handleScheduledAudioFinished(playbackID: UUID) {
    guard currentPlaybackID == playbackID,
          playbackState == .playing,
          let position = renderedPlaybackPosition(),
          position >= duration - Constants.completionTolerance else { return }
    handlePlaybackCompleted()
  }
}

extension AudioEngineManager {
  func startPauseDecay() {
    stopPauseDecay()
    let stream = DisplayLinkStream()
    pauseDecayStream = stream
    pauseDecayTask = Task { @MainActor [weak self] in
      for await _ in stream.frames {
        guard !Task.isCancelled else { break }
        guard let self else {
          stream.stop()
          break
        }

        var decayFactor = Constants.pauseDecayFactor
        let threshold = Constants.pauseDecayThreshold

        var bars = self.visualizerBars
        var barMax: Float = 0
        bars.withUnsafeElementPointer { ptr in
          vDSP_vsmul(ptr, 1, &decayFactor, ptr, 1, 32)
          vDSP_maxv(ptr, 1, &barMax, 32)
        }
        self.visualizerBars = bars

        var levels = self.audioLevels
        var levelMax: Float = 0
        levels.withUnsafeElementPointer { ptr in
          vDSP_vsmul(ptr, 1, &decayFactor, ptr, 1, 1024)
          vDSP_maxv(ptr, 1, &levelMax, 1024)
        }
        self.audioLevels = levels

        var wave = self.waveform
        var waveMax: Float = 0
        wave.withUnsafeElementPointer { ptr in
          vDSP_vsmul(ptr, 1, &decayFactor, ptr, 1, 1024)
          vDSP_maxmgv(ptr, 1, &waveMax, 1024)
        }
        self.waveform = wave

        if barMax < threshold && levelMax < threshold && waveMax < threshold {
          self.visualizerBars = [32 of Float](repeating: 0)
          self.audioLevels = [1024 of Float](repeating: 0)
          self.waveform = [1024 of Float](repeating: 0)
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
}

extension AudioEngineManager {
  func seek(to time: TimeInterval) {
    guard let player,
          let audioFile else { return }
    engineLock.lock()
    defer { engineLock.unlock() }

    let wasPlaying = playbackState == .playing
    playbackState = .seeking
    
    currentPlaybackID = uuid()
    
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
        at: nil,
        completionCallbackType: .dataPlayedBack
      ) { [weak self] _ in
        Task { @MainActor in
          self?.handleScheduledAudioFinished(playbackID: playbackID)
        }
      }
      
      if wasPlaying {
        if startPlayerIfEngineRunning() {
          playbackState = .playing
        } else {
          pause()
          Task { [weak self] in
            await self?.resume()
          }
        }
      } else {
        playbackState = .paused
      }
      
      currentTime = time
    } else {
      currentTime = duration
      handlePlaybackCompleted()
      return
    }
  }
}
