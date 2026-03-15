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

extension DependencyValues {
  var audioEngineManager: AudioEngineManager {
    get { self[AudioEngineManager.self] }
    set { self[AudioEngineManager.self] = newValue }
  }
  
  var lockScreenControlManager: LockScreenControlManager {
    get { self[LockScreenControlManager.self] }
    set { self[LockScreenControlManager.self] = newValue }
  }
}
