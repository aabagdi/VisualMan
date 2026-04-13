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
  private var renderers = [ObjectIdentifier: any MetalVisualizerRenderer]()
  private var inFlightTasks = [ObjectIdentifier: Task<Void, Never>]()

  func renderer<R: MetalVisualizerRenderer>(_ type: R.Type) -> R? {
    renderers[ObjectIdentifier(type)] as? R
  }

  func renderer<R: MetalVisualizerRenderer>(_ type: R.Type, make: @escaping @MainActor () async -> R?) async -> R? {
    let key = ObjectIdentifier(type)
    if let existing = renderers[key] as? R { return existing }

    if let task = inFlightTasks[key] {
      await task.value
      return renderers[key] as? R
    }

    let task = Task<Void, Never> { @MainActor in
      if let new = await make() {
        self.renderers[key] = new
      }
    }
    inFlightTasks[key] = task
    await task.value
    inFlightTasks.removeValue(forKey: key)
    return renderers[key] as? R
  }

  func preWarm() async {
    async let ns: Void = {
      _ = await self.renderer(NavierStokesRenderer.self) { await NavierStokesRenderer.create() }
    }()
    async let ll: Void = {
      _ = await self.renderer(LiquidLightRenderer.self) { await LiquidLightRenderer.create() }
    }()
    async let gol: Void = {
      _ = await self.renderer(GameOfLifeRenderer.self) { await GameOfLifeRenderer.create() }
    }()
    _ = await (ns, ll, gol)
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
