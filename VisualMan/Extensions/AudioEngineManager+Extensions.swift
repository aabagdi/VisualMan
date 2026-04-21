//
//  AudioEngineManager+Timers.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/13/25.
//

import AVFoundation
import Dependencies

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
  func observeAudioSessionInterruptions() {
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
      if playbackState == .playing {
        player?.pause()
        playbackState = .paused
        stopDisplayLink()
        startPauseDecay()
      }
    case .ended:
      try? AVAudioSession.sharedInstance().setActive(true)
      if let engine, !engine.isRunning {
        try? engine.start()
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
