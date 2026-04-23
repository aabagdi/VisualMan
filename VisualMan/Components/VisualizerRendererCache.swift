//
//  VisualizerRendererCache.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/10/26.
//

import SwiftUI

private nonisolated func drainGPU(event: MTLSharedEvent, target: UInt64) {
  event.wait(untilSignaledValue: target, timeoutMS: 1000)
}

@MainActor
@Observable
final class VisualizerRendererCache {
  private var renderers = [ObjectIdentifier: any MetalVisualizerRenderer]()
  private var inFlightTasks = [ObjectIdentifier: Task<Void, Never>]()

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
  
  func resetAll() {
    for renderer in renderers.values {
      renderer.reset()
    }
  }

  func purge() {
    let fenceInfo: [(event: MTLSharedEvent, target: UInt64)] = renderers.values.compactMap { renderer in
      let target = renderer.frameNumber
      renderer.commandQueue.removeResidencySet(renderer.residencySet)
      guard target > 0 else { return nil }
      return (renderer.sharedEvent, target)
    }
    renderers.removeAll()
    sharedDevice = nil
    Task.detached {
      await withTaskGroup(of: Void.self) { group in
        for info in fenceInfo {
          group.addTask { drainGPU(event: info.event, target: info.target) }
        }
      }
    }
  }

  func purge<R: MetalVisualizerRenderer>(_ type: R.Type) {
    let key = ObjectIdentifier(type)
    guard let renderer = renderers.removeValue(forKey: key) else { return }
    renderer.commandQueue.removeResidencySet(renderer.residencySet)
    let target = renderer.frameNumber
    guard target > 0 else { return }
    let event = renderer.sharedEvent
    Task.detached {
      drainGPU(event: event, target: target)
    }
  }
}
