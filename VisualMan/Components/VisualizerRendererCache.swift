//
//  VisualizerRendererCache.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/10/26.
//

import SwiftUI

@MainActor
@Observable
final class VisualizerRendererCache {
  private var renderers: [ObjectIdentifier: any MetalVisualizerRenderer] = [:]

  func renderer<R: MetalVisualizerRenderer>(_ type: R.Type, make: () -> R?) -> R? {
    let key = ObjectIdentifier(type)
    if let existing = renderers[key] as? R { return existing }
    guard let new = make() else { return nil }
    renderers[key] = new
    return new
  }

  func resetAll() {
    for renderer in renderers.values {
      renderer.reset()
    }
  }

  func purge() {
    renderers.removeAll()
  }

  func purge<R: MetalVisualizerRenderer>(_ type: R.Type) {
    renderers.removeValue(forKey: ObjectIdentifier(type))
  }
}
