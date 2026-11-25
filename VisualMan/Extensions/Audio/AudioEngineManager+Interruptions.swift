//
//  AudioEngineManager+Interruptions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

import AVFoundation
import os

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
      MainActor.assumeIsolated {
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
      MainActor.assumeIsolated {
        self?.handleRouteChange(reason: reason)
      }
    }

    configChangeObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        await self?.handleEngineConfigChange()
      }
    }
  }

  private func handleInterruption(type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions?) {
    switch type {
    case .began:
      let wasPlaying = playbackState == .playing
      if wasPlaying {
        pause()
      }
      resumesAfterInterruption = wasPlaying
    case .ended:
      Task { [weak self] in
        await self?.reactivateAfterInterruption(options: options)
      }
    @unknown default:
      break
    }
  }

  private var shouldStillResumeAfterInterruption: Bool {
    resumesAfterInterruption && playbackState == .paused
  }

  private func reactivateAfterInterruption(options: AVAudioSession.InterruptionOptions?) async {
    guard shouldStillResumeAfterInterruption, let options, options.contains(.shouldResume) else {
      resumesAfterInterruption = false
      return
    }
    do {
      try await activateAudioSession()
    } catch {
      audioLogger.error("Failed to reactivate audio session after interruption: \(error.localizedDescription)")
    }
    guard shouldStillResumeAfterInterruption else { return }
    if let engine, !engine.isRunning {
      do {
        try await startEngine(engine)
      } catch {
        audioLogger.error("Failed to restart engine after interruption: \(error.localizedDescription)")
      }
      guard shouldStillResumeAfterInterruption else {
        if playbackState != .playing {
          engineLock.withLock {
            engineShouldRun.withLock { $0 = false }
            engine.pause()
          }
        }
        return
      }
    }
    resumesAfterInterruption = false
    guard startPlayerIfEngineRunning() else { return }
    stopPauseDecay()
    playbackState = .playing
    startDisplayLink()
  }

  private func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
    switch reason {
    case .oldDeviceUnavailable:
      if playbackState == .playing {
        pause()
      }
    case .newDeviceAvailable:
      break
    default:
      break
    }
  }

  private func handleEngineConfigChange() async {
    guard let engine else { return }
    guard playbackState == .playing else { return }
    engineLock.withLock { player?.pause() }
    stopDisplayLink()
    do {
      try await startEngine(engine)
    } catch {
      audioLogger.error("Failed to restart engine after config change: \(error.localizedDescription)")
    }
    guard playbackState == .playing else { return }
    engineLock.withLock {
      engine.mainMixerNode.removeTap(onBus: 0)
      installAudioTap(on: engine)
    }
    guard startPlayerIfEngineRunning() else {
      pause()
      return
    }
    startDisplayLink()
  }
}
