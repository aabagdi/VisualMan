//
//  AudioPlaylistManager.swift
//  VisualMan
//
//  Created by Your Name on Date.
//

import Foundation
import Combine

@Observable
final class AudioPlaylistManager {
  var audioSources: [any AudioSource] = []
  var currentIndex: Int = 0
  
  func setPlaylist(_ sources: [any AudioSource], startingIndex: Int = 0) {
    self.audioSources = sources
    self.currentIndex = startingIndex
  }
  
  func clearPlaylist() {
    self.audioSources = []
    self.currentIndex = 0
  }
  
  var currentAudioSource: (any AudioSource)? {
    guard currentIndex >= 0 && currentIndex < audioSources.count else { return nil }
    return audioSources[currentIndex]
  }
  
  var hasNext: Bool {
    currentIndex < audioSources.count - 1
  }
  
  var hasPrevious: Bool {
    currentIndex > 0
  }
  
  func moveToNext() {
    if hasNext {
      currentIndex += 1
    }
  }
  
  func moveToPrevious() {
    if hasPrevious {
      currentIndex -= 1
    }
  }
  
  func moveToIndex(_ index: Int) {
    guard index >= 0 && index < audioSources.count else { return }
    currentIndex = index
  }
}
