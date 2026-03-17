//
//  LockScreenControlManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import Foundation
import MediaPlayer
import Dependencies

@MainActor
final class LockScreenControlManager: @unchecked Sendable {
  
  @Dependency(AudioEngineManager.self) private var audioManager
  private let placeholder = UIImage(resource: .artPlaceholder)
  
  var onPlayPause: (() -> Void)?
  var onNext: (() -> Void)?
  var onPrevious: (() -> Void)?
  
  init() {
    setupRemoteTransportControls()
  }
  
  private func setupRemoteTransportControls() {
    let commandCenter = MPRemoteCommandCenter.shared()
    
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = true
    
    commandCenter.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onPlayPause?() }
      return .success
    }
    
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onPlayPause?() }
      return .success
    }
    
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onNext?() }
      return .success
    }
    
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onPrevious?() }
      return .success
    }
    
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let position = positionEvent.positionTime
      Task { @MainActor in self?.seek(to: position) }
      return .success
    }
  }
  
  private func seek(to time: TimeInterval) {
    audioManager.seek(to: time)
  }
  
  func updateTrackInfo(title: String?,
                       artist: String?,
                       albumArt: UIImage?,
                       duration: TimeInterval) {
    let artwork: UIImage = albumArt ?? placeholder
    
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "Unknown"
    nowPlayingInfo[MPMediaItemPropertyArtist] = artist ?? "Unknown"
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { @Sendable _ in
      artwork
    }
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }
  
  func updatePlaybackPosition(currentTime: TimeInterval, isPlaying: Bool) {
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }
  
  func activate() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.isEnabled = true
  }
  
  func cleanup() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = false
    commandCenter.pauseCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    
    onPlayPause = nil
    onNext = nil
    onPrevious = nil
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }
}
