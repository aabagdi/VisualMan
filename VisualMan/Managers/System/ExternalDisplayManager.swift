//
//  ExternalDisplayManager.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/20/26.
//

import Observation

@Observable
@MainActor
final class ExternalDisplayManager {
  private(set) var isConnected = false

  func sceneConnected() {
    isConnected = true
  }

  func sceneDisconnected() {
    isConnected = false
  }
}
