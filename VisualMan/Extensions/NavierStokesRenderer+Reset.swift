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
          let resetCmd = device.makeCommandBuffer() else { return }

    resetCmd.beginCommandBuffer(allocator: allocator)
    resetCmd.useResidencySet(residencySet)

    guard let encoder = resetCmd.makeComputeCommandEncoder() else {
      resetCmd.endCommandBuffer()
      return
    }
    encoder.setArgumentTable(argumentTable)

    encoder.setComputePipelineState(pipelines.clearRGBA)
    let allTextures: [MTLTexture] = [
      velocityA, velocityB, pressure, divergenceTexture,
      psiA, psiB, psiC, u0,
      dyeA, dyeB, dyeC,
      bloomA, bloomB,
      bloomMidA, bloomLoA
    ]
    for tex in allTextures {
      argumentTable.setTexture(tex.gpuResourceID, index: 0)
      dispatchGrid(encoder: encoder, width: tex.width, height: tex.height)
    }

    encoder.endEncoding()
    resetCmd.endCommandBuffer()

    let resetValue = frameNumber + 1000
    commandQueue.commit([resetCmd])
    commandQueue.signalEvent(sharedEvent, value: resetValue)

    frameNumber = resetValue

    framesSinceReinit = reinitInterval
  }
}
