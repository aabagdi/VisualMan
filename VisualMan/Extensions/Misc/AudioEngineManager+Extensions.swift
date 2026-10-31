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
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      audioLogger.error("Failed to activate audio session on resume: \(error.localizedDescription)")
    }
    if let engine, !engine.isRunning {
      do {
        try engine.start()
      } catch {
        audioLogger.error("Failed to restart audio engine on resume: \(error.localizedDescription)")
      }
    }
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
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      audioLogger.error("Failed to deactivate audio session: \(error.localizedDescription)")
    }
  }

  func startNowPlayingTimer(updateHandler: @escaping @MainActor () -> Void) {
    stopNowPlayingTimer()
    nowPlayingTask = Task { @MainActor [weak self] in
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
    displayLinkTask = Task { @MainActor [weak self] in
      for await _ in stream.frames {
        guard !Task.isCancelled, let self else { break }
        self.updateTime()
        await self.audioTapProcessor.tick { result in
          self.audioLevels = result.audioLevels
          self.visualizerBars = result.visualizerBars
          self.waveform = result.waveform
        }
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
      
      if currentTime >= duration - 0.05 && playbackState == .playing {
        handlePlaybackCompleted()
      }
    }
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
  func observeAudioSessionInterruptions() {
    interruptionObserver = NotificationCenter.default.addObserver(
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

    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main
    ) { [weak self] notification in
      guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
      Task { @MainActor in
        self?.handleRouteChange(reason: reason)
      }
    }

    configChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.handleEngineConfigChange()
      }
    }
  }
  
  private func handleInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions?) {
    switch type {
    case .began:
      if playbackState == .playing {
        player?.pause()
        playbackState = .paused
        stopDisplayLink()
        startPauseDecay()
      }
    case .ended:
      do {
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        audioLogger.error("Failed to reactivate audio session after interruption: \(error.localizedDescription)")
      }
      if let engine, !engine.isRunning {
        do {
          try engine.start()
        } catch {
          audioLogger.error("Failed to restart engine after interruption: \(error.localizedDescription)")
        }
      }
      if let options, options.contains(.shouldResume) {
        stopPauseDecay()
        player?.play()
        playbackState = .playing
        startDisplayLink()
      }
    @unknown default:
      break
    }
  }
  
  private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
    switch reason {
    case .oldDeviceUnavailable:
      if playbackState == .playing {
        player?.pause()
        playbackState = .paused
        stopDisplayLink()
        startPauseDecay()
      }
    case .newDeviceAvailable:
      break
    default:
      break
    }
  }

  private func handleEngineConfigChange() {
    guard let engine else { return }
    let wasPlaying = playbackState == .playing
    if wasPlaying {
      player?.pause()
      stopDisplayLink()
    }
    do {
      try engine.start()
    } catch {
      audioLogger.error("Failed to restart engine after config change: \(error.localizedDescription)")
    }
    if wasPlaying {
      engine.mainMixerNode.removeTap(onBus: 0)
      installAudioTap(on: engine)
      player?.play()
      playbackState = .playing
      startDisplayLink()
    }
  }

  func seek(to time: TimeInterval) {
    guard let player,
          let audioFile else { return }
    
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
        at: nil
      ) { [weak self] in
        Task { @MainActor in
          guard let self,
                self.currentPlaybackID == playbackID else { return }
          self.handlePlaybackCompleted()
        }
      }
      
      if wasPlaying {
        if let engine, !engine.isRunning {
          do {
            try engine.start()
          } catch {
            audioLogger.error("Failed to restart engine during seek: \(error.localizedDescription)")
          }
        }
        player.play()
        playbackState = .playing
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
