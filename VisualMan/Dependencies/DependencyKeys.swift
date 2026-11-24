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

extension HapticsManager: DependencyKey {
  static var liveValue: HapticsManager { HapticsManager() }
}

extension ExternalDisplayManager: DependencyKey {
  static var liveValue: ExternalDisplayManager { ExternalDisplayManager() }
}

extension VisualizerSelection: DependencyKey {
  static var liveValue: VisualizerSelection { VisualizerSelection() }
}

extension VisualizerRendererCache: DependencyKey {
  static var liveValue: VisualizerRendererCache { VisualizerRendererCache() }
}

extension VisualizerSnapshotter: DependencyKey {
  static var liveValue: VisualizerSnapshotter { VisualizerSnapshotter() }
}
