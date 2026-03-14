//
//  MusicPlayerViewModel.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/10/26.
//

import Foundation
import Combine

extension MusicPlayerView {
  @Observable
  @MainActor
  final class MusicPlayerViewModel {
    private let audioManager = AudioEngineManager.shared
    private let lockScreen = LockScreenControlManager.shared
    
    @ObservationIgnored private var playbackCompletionCancellable: AnyCancellable?
    
    var failedPlaying: Bool = false
    var playingError: VMError?
    
    func start(playlistManager: AudioPlaylistManager, audioSources: [any AudioSource], startingIndex: Int) {
      playlistManager.setPlaylist(audioSources, startingIndex: startingIndex)
      setupLockScreenControls(playlistManager: playlistManager)
      
      playbackCompletionCancellable = audioManager.playbackCompleted
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          self?.onSongCompleted(playlistManager: playlistManager)
        }
      
      let currentSourceURL = playlistManager.currentAudioSource?.getPlaybackURL()
      let alreadyLoaded = currentSourceURL != nil && audioManager.currentAudioSourceURL == currentSourceURL
      if !alreadyLoaded {
        playCurrentSong(playlistManager: playlistManager)
      }
      
      audioManager.startNowPlayingTimer {
        self.updateNowPlayingInfo(playlistManager: playlistManager)
      }
    }
    
    func cleanup() {
      playbackCompletionCancellable?.cancel()
      playbackCompletionCancellable = nil
    }
    
    func togglePlayback(playlistManager: AudioPlaylistManager) {
      if audioManager.isPlaying {
        audioManager.pause()
      } else if audioManager.currentTime > 0 && audioManager.currentTime < audioManager.duration {
        audioManager.resume()
      } else {
        playCurrentSong(playlistManager: playlistManager)
      }
      updateNowPlayingInfo(playlistManager: playlistManager)
    }
    
    func skipBackwards(playlistManager: AudioPlaylistManager) {
      if audioManager.currentTime >= 3 {
        audioManager.seek(to: 0)
      } else if playlistManager.hasPrevious {
        audioManager.stop()
        playlistManager.moveToPrevious()
        playCurrentSong(playlistManager: playlistManager)
      } else if playlistManager.currentIndex == 0 {
        audioManager.seek(to: 0)
      }
    }
    
    func skipForwards(playlistManager: AudioPlaylistManager) {
      guard playlistManager.hasNext else { return }
      audioManager.stop()
      playlistManager.moveToNext()
      playCurrentSong(playlistManager: playlistManager)
    }
    
    private func playCurrentSong(playlistManager: AudioPlaylistManager) {
      guard let source = playlistManager.currentAudioSource else { return }
      
      do {
        try audioManager.play(source)
        updateNowPlayingInfo(playlistManager: playlistManager)
      } catch let error as VMError {
        playingError = error
        failedPlaying = true
      } catch {
        playingError = VMError.failedToPlay
        failedPlaying = true
      }
    }
    
    private func onSongCompleted(playlistManager: AudioPlaylistManager) {
      audioManager.stop()
      
      if playlistManager.hasNext {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
          playlistManager.moveToNext()
          self.playCurrentSong(playlistManager: playlistManager)
        }
      } else {
        playlistManager.moveToIndex(0)
      }
    }
    
    private func setupLockScreenControls(playlistManager: AudioPlaylistManager) {
      lockScreen.onPlayPause = { [weak self] in
        self?.togglePlayback(playlistManager: playlistManager)
      }
      
      lockScreen.onNext = { [weak self] in
        self?.skipForwards(playlistManager: playlistManager)
      }
      
      lockScreen.onPrevious = { [weak self] in
        self?.skipBackwards(playlistManager: playlistManager)
      }
    }
    
    private func updateNowPlayingInfo(playlistManager: AudioPlaylistManager) {
      guard let source = playlistManager.currentAudioSource else { return }
      
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
