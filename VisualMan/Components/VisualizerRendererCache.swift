//
//  VisualizerRendererCache.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/10/26.
//

import SwiftUI
import os

#if !targetEnvironment(simulator)
@MainActor
@Observable
final class VisualizerRendererCache {
  @ObservationIgnored
  private var renderers = [ObjectIdentifier: any MetalVisualizerRenderer]()
  @ObservationIgnored
  private var inFlightTasks = [ObjectIdentifier: Task<Void, Never>]()
  @ObservationIgnored
  private var useCounts = [ObjectIdentifier: Int]()

  @ObservationIgnored
  private(set) var sharedDevice: MTLDevice?

  private func getOrCreateDevice() -> MTLDevice? {
    if let device = sharedDevice { return device }
    sharedDevice = MTLCreateSystemDefaultDevice()
    return sharedDevice
  }

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
      let signpostID = pointsOfInterest.makeSignpostID()
      let createState = pointsOfInterest.beginInterval("Create Renderer", id: signpostID,
                                                       "\(String(describing: type), privacy: .public)")
      let new = await make()
      pointsOfInterest.endInterval("Create Renderer", createState)
      if let new, !Task.isCancelled {
        self.renderers[key] = new
      }
    }
    inFlightTasks[key] = task
    await task.value
    if inFlightTasks[key] == task {
      inFlightTasks.removeValue(forKey: key)
    }
    return renderers[key] as? R
  }

  func beginUse<R: MetalVisualizerRenderer>(_ type: R.Type) {
    useCounts[ObjectIdentifier(type), default: 0] += 1
  }

  func endUse<R: MetalVisualizerRenderer>(_ type: R.Type) {
    let key = ObjectIdentifier(type)
    let count = (useCounts[key] ?? 0) - 1
    useCounts[key] = count > 0 ? count : nil
  }

  func preWarm() async {
    guard let device = getOrCreateDevice() else { return }
    async let ns: NavierStokesRenderer? = renderer(
      NavierStokesRenderer.self
    ) { await NavierStokesRenderer.create(device: device) }
    async let ll: LiquidLightRenderer? = renderer(
      LiquidLightRenderer.self
    ) { await LiquidLightRenderer.create(device: device) }
    async let gol: GameOfLifeRenderer? = renderer(
      GameOfLifeRenderer.self
    ) { await GameOfLifeRenderer.create(device: device) }
    async let abex: AbstractExpressionismRenderer? = renderer(
      AbstractExpressionismRenderer.self
    ) { await AbstractExpressionismRenderer.create(device: device) }
    _ = await (ns, ll, gol, abex)
  }
  
  func purge() {
    for (key, task) in inFlightTasks where useCounts[key] == nil {
      task.cancel()
      inFlightTasks.removeValue(forKey: key)
    }
    renderers = renderers.filter { key, renderer in
      useCounts[key] != nil || renderer.sharedEvent.signaledValue < renderer.frameNumber
    }
    if renderers.isEmpty && inFlightTasks.isEmpty {
      sharedDevice = nil
    }
  }
}
#else

@MainActor
@Observable
final class VisualizerRendererCache {
  func preWarm() async {}
  func purge() {}
}
#endif
