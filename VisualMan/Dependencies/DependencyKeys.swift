//
//  DependencyKeys.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import Dependencies

extension AudioEngineManager: DependencyKey {
  static var liveValue: AudioEngineManager { AudioEngineManager() }
}

extension LockScreenControlManager: DependencyKey {
  static var liveValue: LockScreenControlManager { LockScreenControlManager() }
}

extension AudioPlaylistManager: DependencyKey {
  static var liveValue: AudioPlaylistManager { AudioPlaylistManager() }
}

extension MusicLibraryAccessManager: DependencyKey {
  static var liveValue: MusicLibraryAccessManager { MusicLibraryAccessManager() }
}
