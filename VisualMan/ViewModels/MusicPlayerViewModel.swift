//
//  MusicPlayerViewModel.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/10/26.
//

import Foundation

extension MusicPlayerView {
  @Observable
  @MainActor
  final class MusicPlayerViewModel {
    private let audioManager = AudioEngineManager.shared
    private let lockScreen = LockScreenControlManager.shared
    
    @ObservationIgnored private var playbackListeningTask: Task<Void, Never>?
    @ObservationIgnored private var songTransitionTask: Task<Void, Never>?
    @ObservationIgnored private weak var playlistManager: AudioPlaylistManager?
    
    var failedPlaying: Bool = false
    var playingError: VMError?
    
    func start(playlistManager: AudioPlaylistManager, audioSources: [any AudioSource], startingIndex: Int) {
      self.playlistManager = playlistManager
      playlistManager.setPlaylist(audioSources, startingIndex: startingIndex)
      setupLockScreenControls()
      
      playbackListeningTask?.cancel()
      playbackListeningTask = Task { [weak self] in
        guard let stream = self?.audioManager.playbackCompleted else { return }
        for await _ in stream {
          guard !Task.isCancelled else { break }
          self?.onSongCompleted()
        }
      }
      
      let currentSourceURL = playlistManager.currentAudioSource?.getPlaybackURL()
      let alreadyLoaded = currentSourceURL != nil && audioManager.currentAudioSourceURL == currentSourceURL
      if !alreadyLoaded {
        playCurrentSong()
      }
      
      audioManager.startNowPlayingTimer { [weak self] in
        self?.updateNowPlayingInfo()
      }
    }
    
    func cleanup() {
      playbackListeningTask?.cancel()
      playbackListeningTask = nil
      songTransitionTask?.cancel()
      songTransitionTask = nil
      lockScreen.onPlayPause = nil
      lockScreen.onNext = nil
      lockScreen.onPrevious = nil
    }
    
    func togglePlayback() {
      if audioManager.isPlaying {
        audioManager.pause()
      } else if audioManager.currentTime > 0 && audioManager.currentTime < audioManager.duration {
        audioManager.resume()
      } else {
        playCurrentSong()
      }
      updateNowPlayingInfo()
    }
    
    func skipBackwards() {
      guard let playlistManager else { return }
      if audioManager.currentTime >= 3 {
        audioManager.seek(to: 0)
      } else if playlistManager.hasPrevious {
        audioManager.stop()
        playlistManager.moveToPrevious()
        playCurrentSong()
      } else if playlistManager.currentIndex == 0 {
        audioManager.seek(to: 0)
      }
    }
    
    func skipForwards() {
      guard let playlistManager, playlistManager.hasNext else { return }
      audioManager.stop()
      playlistManager.moveToNext()
      playCurrentSong()
    }
    
    private func playCurrentSong() {
      guard let source = playlistManager?.currentAudioSource else { return }
      
      do {
        try audioManager.play(source)
        updateNowPlayingInfo()
      } catch let error as VMError {
        playingError = error
        failedPlaying = true
      } catch {
        playingError = VMError.failedToPlay
        failedPlaying = true
      }
    }
    
    private func onSongCompleted() {
      guard let playlistManager else { return }
      audioManager.stop()
      
      if playlistManager.hasNext {
        songTransitionTask?.cancel()
        songTransitionTask = Task {
          try? await Task.sleep(for: .milliseconds(100))
          guard !Task.isCancelled else { return }
          playlistManager.moveToNext()
          playCurrentSong()
        }
      } else {
        playlistManager.moveToIndex(0)
      }
    }
    
    private func setupLockScreenControls() {
      lockScreen.onPlayPause = { [weak self] in
        self?.togglePlayback()
      }
      
      lockScreen.onNext = { [weak self] in
        self?.skipForwards()
      }
      
      lockScreen.onPrevious = { [weak self] in
        self?.skipBackwards()
      }
    }
    
    private func updateNowPlayingInfo() {
      guard let source = playlistManager?.currentAudioSource else { return }
      
      lockScreen.updateNowPlayingInfo(
        title: source.title,
        artist: source.artist,
        albumArt: source.albumArt,
        duration: audioManager.duration,
        currentTime: audioManager.currentTime,
        isPlaying: audioManager.isPlaying
      )
    }
  }
}
