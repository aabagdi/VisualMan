//
//  DependencyKeys.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import Dependencies

extension AudioEngineManager: DependencyKey {
  @MainActor static var liveValue: AudioEngineManager { AudioEngineManager() }
}

extension LockScreenControlManager: DependencyKey {
  @MainActor static var liveValue: LockScreenControlManager { LockScreenControlManager() }
}
