//
//  DependencyKeys.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import Dependencies

extension AudioEngineManager: DependencyKey {
  @MainActor static let liveValue = AudioEngineManager()
}

extension LockScreenControlManager: DependencyKey {
  @MainActor static let liveValue = LockScreenControlManager()
}

extension AudioPlaylistManager: DependencyKey {
  @MainActor static let liveValue = AudioPlaylistManager()
}

extension MusicLibraryAccessManager: DependencyKey {
  @MainActor static let liveValue = MusicLibraryAccessManager()
}
