//
//  NavierStokesRenderer+Reset.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/10/26.
//

import Metal

extension NavierStokesRenderer {
  func reset() {
    time = 0
    prevBass = 0
    prevMid = 0
    
    guard let allocator = device.makeCommandAllocator(),
          let resetCmd = device.makeCommandBuffer(),
          let resetEvent = device.makeSharedEvent() else {
      return
    }

    resetCmd.beginCommandBuffer(allocator: allocator)
    resetCmd.useResidencySet(residencySet)

    guard let encoder = resetCmd.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    encoder.setComputePipelineState(pipelines.clearRG)
    let rgTextures: [MTLTexture] = [
      velocityA, velocityB, pressure, divergenceTexture,
      psiA, psiB, psiC, u0
    ]
    for tex in rgTextures {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder, width: tex.width, height: tex.height)
    }

    encoder.setComputePipelineState(pipelines.clearRGBA)
    let rgbaTextures: [MTLTexture] = [
      dyeA, dyeB, dyeC,
      bloomA, bloomB,
      bloomMidA, bloomLoA
    ]
    for tex in rgbaTextures {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder, width: tex.width, height: tex.height)
    }

    encoder.endEncoding()
    resetCmd.endCommandBuffer()

    commandQueue.commit([resetCmd])
    commandQueue.signalEvent(resetEvent, value: 1)

    resetEvent.wait(untilSignaledValue: 1, timeoutMS: 1000)

    framesSinceReinit = reinitInterval
  }
}
