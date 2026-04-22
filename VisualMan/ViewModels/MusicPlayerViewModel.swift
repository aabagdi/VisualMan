//
//  MusicPlayerViewModel.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/10/26.
//

import Foundation
import Dependencies

extension MusicPlayerView {
  @Observable
  @MainActor
  final class MusicPlayerViewModel {
    @ObservationIgnored @Dependency(AudioEngineManager.self) private var audioManager
    @ObservationIgnored @Dependency(LockScreenControlManager.self) private var lockScreen
    @ObservationIgnored @Dependency(AudioPlaylistManager.self) private var playlistManager
    @ObservationIgnored @Dependency(\.continuousClock) var clock
    
    @ObservationIgnored private var playbackListeningTask: Task<Void, Never>?
    @ObservationIgnored private var songTransitionTask: Task<Void, Never>?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var lastArtworkSourceURL: URL?
        
    var failedPlaying: Bool = false
    var playingError: VMError?
    
    func start(audioSources: [any AudioSource], startingIndex: Int) {
      playTask?.cancel()
      songTransitionTask?.cancel()

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
      playTask?.cancel()
      playTask = nil
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
      if audioManager.currentTime >= 3 {
        audioManager.seek(to: 0)
      } else if playlistManager.hasPrevious {
        audioManager.stopForTransition()
        playlistManager.moveToPrevious()
        playCurrentSong()
      } else if playlistManager.currentIndex == 0 {
        audioManager.seek(to: 0)
      }
    }
    
    func skipForwards() {
      guard playlistManager.hasNext else { return }
      audioManager.stopForTransition()
      playlistManager.moveToNext()
      playCurrentSong()
    }
    
    private func playCurrentSong() {
      guard let source = playlistManager.currentAudioSource else { return }
      
      playTask?.cancel()
      playTask = Task {
        do {
          try await audioManager.play(source)
          guard !Task.isCancelled else { return }
          updateNowPlayingInfo()
        } catch let error as VMError {
          playingError = error
          failedPlaying = true
        } catch {
          playingError = VMError.failedToPlay(underlying: error)
          failedPlaying = true
        }
      }
    }
    
    private func onSongCompleted() {
      if playlistManager.hasNext {
        audioManager.stopForTransition()
        songTransitionTask?.cancel()
        songTransitionTask = Task {
          try? await clock.sleep(for: .milliseconds(100))
          guard !Task.isCancelled else { return }
          playlistManager.moveToNext()
          playCurrentSong()
        }
      } else {
        audioManager.stop()
        lockScreen.cleanup()
        playlistManager.moveToIndex(0)
      }
    }
    
    private func setupLockScreenControls() {
      lockScreen.activate()
      
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
      guard let source = playlistManager.currentAudioSource else { return }
      
      let sourceURL = source.getPlaybackURL()
      if sourceURL != lastArtworkSourceURL {
        lastArtworkSourceURL = sourceURL
        lockScreen.updateTrackInfo(
          title: source.title,
          artist: source.artist,
          albumArt: source.albumArt,
          duration: audioManager.duration
        )
      }
      
      lockScreen.updatePlaybackPosition(
        currentTime: audioManager.currentTime,
        isPlaying: audioManager.isPlaying
      )
    }
  }
}
