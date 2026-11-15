//
//  NavierStokesRenderer+Multigrid.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 10/31/26.
//

#if !targetEnvironment(simulator)
import Metal

extension NavierStokesRenderer {
  func projectPressureMultigrid(encoder: any MTL4ComputeCommandEncoder, cycles: Int) {
    let coarsest = mgPressure.count - 1
    guard coarsest > 0 else {
      projectPressureDirect(encoder: encoder)
      return
    }

    let cycles = max(cycles, 1)
    for cycle in 0..<cycles {
      if cycle == 0 {
        encoder.setComputePipelineState(pipelines.mgDescendDivergence)
        argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
      } else {
        encoder.setComputePipelineState(pipelines.mgDescend)
        argumentTable.setTexture(mgCorrected[0].gpuResourceID, index: 0)
      }
      argumentTable.setTexture(mgRHS[0].gpuResourceID, index: 1)
      argumentTable.setTexture(mgPressure[0].gpuResourceID, index: 2)
      argumentTable.setTexture(mgRHS[1].gpuResourceID, index: 3)
      dispatchTiles(encoder: encoder, level: 0)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

      for level in 1..<coarsest {
        encoder.setComputePipelineState(pipelines.mgDescendZero)
        argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 0)
        argumentTable.setTexture(mgPressure[level].gpuResourceID, index: 1)
        argumentTable.setTexture(mgRHS[level + 1].gpuResourceID, index: 2)
        dispatchTiles(encoder: encoder, level: level)
        encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      }

      multigridCoarseSolve(encoder: encoder, level: coarsest)

      for level in stride(from: coarsest - 1, through: 0, by: -1) {
        let isLast = level == 0 && cycle == cycles - 1
        encoder.setComputePipelineState(isLast ? pipelines.mgAscendProject : pipelines.mgAscend)
        argumentTable.setTexture(mgPressure[level].gpuResourceID, index: 0)
        argumentTable.setTexture(mgCorrected[level + 1].gpuResourceID, index: 1)
        argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 2)
        if isLast {
          argumentTable.setTexture(velocityA.gpuResourceID, index: 3)
          argumentTable.setAddress(writeUniform(Self.maxSpeed), index: 0)
          dispatchTiles(encoder: encoder, level: level)
        } else {
          argumentTable.setTexture(mgCorrected[level].gpuResourceID, index: 3)
          dispatchTiles(encoder: encoder, level: level)
          encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
        }
      }
    }
  }

  private func projectPressureDirect(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.divergenceRHS)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(mgRHS[0].gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    multigridCoarseSolve(encoder: encoder, level: 0)

    gradientSubtract(encoder: encoder, pressure: mgCorrected[0])
  }

  private func dispatchTiles(encoder: any MTL4ComputeCommandEncoder, level: Int) {
    let pressure = mgPressure[level]
    let groups = MTLSize(width: (pressure.width + 15) / 16, height: (pressure.height + 15) / 16, depth: 1)
    let groupSize = MTLSize(width: 16, height: 16, depth: 1)
    encoder.dispatchThreadgroups(threadgroupsPerGrid: groups, threadsPerThreadgroup: groupSize)
  }

  private func multigridCoarseSolve(encoder: any MTL4ComputeCommandEncoder,
                                    level: Int) {
    let pipeline = pipelines.mgCoarseSolve
    encoder.setComputePipelineState(pipeline)
    argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 0)
    argumentTable.setTexture(mgCorrected[level].gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(UInt32(Self.multigridCoarseSweeps)), index: 0)
    let threads = min(1024, pipeline.maxTotalThreadsPerThreadgroup)
    encoder.dispatchThreadgroups(threadgroupsPerGrid: MTLSize(width: 1, height: 1, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1))
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }
}

#endif
