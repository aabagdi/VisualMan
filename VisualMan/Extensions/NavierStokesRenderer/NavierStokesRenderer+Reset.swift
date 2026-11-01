//
//  NavierStokesRenderer+Reset.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/10/26.
//

#if !targetEnvironment(simulator)
import Metal

extension NavierStokesRenderer {
  func reset() {
    time = 0
    prevBass = 0
    prevMid = 0
    dynamicsWarm = false
    lastExcitement = 0

    sharedEvent.wait(untilSignaledValue: frameNumber, timeoutMS: 1000)

    pendingTAAHistoryReleases.forEach { residencySet.removeAllocation($0.texture) }
    pendingTAAHistoryReleases.removeAll()
    residencySet.commit()

    clearSimulationTextures()
  }

  func clearSimulationTextures() {
    runMaintenancePass(wait: false) { encoder in
      encodeClear(encoder: encoder)
    }
    framesSinceReinit = Self.reinitMaxInterval
    resetFlowStats()
  }

  func carryOverSimulation(dye oldDye: MTLTexture, velocity oldVelocity: MTLTexture) {
    let scale = SIMD4<Float>(Float(gridWidth) / Float(oldVelocity.width),
                             Float(gridHeight) / Float(oldVelocity.height), 0, 0)
    runMaintenancePass(wait: true) { encoder in
      encodeClear(encoder: encoder)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

      encoder.setComputePipelineState(pipelines.resample)
      argumentTable.setTexture(oldDye.gpuResourceID, index: 0)
      argumentTable.setTexture(dyeA.gpuResourceID, index: 1)
      argumentTable.setAddress(writeUniform(SIMD4<Float>(repeating: 1)), index: 0)
      dispatchGrid(encoder: encoder)

      argumentTable.setTexture(oldVelocity.gpuResourceID, index: 0)
      argumentTable.setAddress(writeUniform(scale), index: 0)
      for target in [velocityA, u0] {
        argumentTable.setTexture(target.gpuResourceID, index: 1)
        dispatchGrid(encoder: encoder)
      }

      encoder.setComputePipelineState(pipelines.psiInit)
      argumentTable.setTexture(psiA.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder)
    }
    framesSinceReinit = 0
    resetFlowStats()
  }

  private func encodeClear(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.clearRGBA)
    for tex in allSimulationTextures {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder, width: tex.width, height: tex.height)
    }
  }

  private func resetFlowStats() {
    memset(stretchStatsBuffer.contents(), 0, stretchStatsBuffer.length)
    lastStretchedFraction = 0
    lastFastFraction = 0
  }

  private func runMaintenancePass(wait: Bool, _ body: (any MTL4ComputeCommandEncoder) -> Void) {
    guard let allocator = device.makeCommandAllocator(),
          let cmd = device.makeCommandBuffer() else { return }

    cmd.beginCommandBuffer(allocator: allocator)
    cmd.useResidencySet(residencySet)
    guard let encoder = cmd.makeComputeCommandEncoder() else {
      cmd.endCommandBuffer()
      return
    }
    encoder.setArgumentTable(argumentTable)
    body(encoder)
    encoder.endEncoding()
    cmd.endCommandBuffer()

    let value = frameNumber + 1
    commandQueue.commit([cmd])
    commandQueue.signalEvent(sharedEvent, value: value)
    frameNumber = value
    if wait {
      sharedEvent.wait(untilSignaledValue: value, timeoutMS: 1000)
    }
  }
}

#endif
