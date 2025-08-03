//
//  LockScreenControlManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/2/25.
//

import Foundation
import MediaPlayer

final class LockScreenControlManager {
  static let shared = LockScreenControlManager()
  
  private let audioManager = AudioEngineManager.shared
  private let placeholder = UIImage(named: "Art Placeholder")!
  
  var onPlayPause: (() -> Void)?
  var onNext: (() -> Void)?
  var onPrevious: (() -> Void)?
  
  private init() {
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
      DispatchQueue.main.async {
        self?.onPlayPause?()
      }
      return .success
    }
    
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.onPlayPause?()
      }
      return .success
    }
    
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.onNext?()
      }
      return .success
    }
    
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.onPrevious?()
      }
      return .success
    }
    
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      DispatchQueue.main.async {
        self.seek(to: positionEvent.positionTime)
      }
      return .success
    }
  }
  
  private func seek(to time: TimeInterval) {
    audioManager.seek(to: time)
  }
  
  func updateNowPlayingInfo(title: String?, artist: String?, albumArt: UIImage?, duration: TimeInterval, currentTime: TimeInterval, isPlaying: Bool) {
    let artwork: UIImage = albumArt ?? placeholder
    
    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "Unknown"
    nowPlayingInfo[MPMediaItemPropertyArtist] = artist ?? "Unknown"
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    
    nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { @Sendable _ in
      artwork
    }
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }
  
  func cleanup() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = false
    commandCenter.pauseCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }
}
