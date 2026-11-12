//
//  NavierStokesRenderer+Multigrid.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 10/31/26.
//

#if !targetEnvironment(simulator)
import Metal

extension NavierStokesRenderer {
  func projectPressureMultigrid(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.divergenceRHS)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(mgRHS[0].gpuResourceID, index: 1)
    argumentTable.setTexture(mgPressure[0].gpuResourceID, index: 2)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    for _ in 0..<Self.multigridCycles {
      multigridVCycle(encoder: encoder)
    }

    gradientSubtract(encoder: encoder, pressure: mgPressure[0])
  }

  private func multigridVCycle(encoder: any MTL4ComputeCommandEncoder) {
    let coarsest = mgPressure.count - 1

    for level in 0..<coarsest {
      multigridSmooth(encoder: encoder, level: level, sweeps: Self.multigridPreSmooth)

      let coarse = mgPressure[level + 1]
      encoder.setComputePipelineState(pipelines.mgRestrict)
      argumentTable.setTexture(mgPressure[level].gpuResourceID, index: 0)
      argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 1)
      argumentTable.setTexture(mgRHS[level + 1].gpuResourceID, index: 2)
      argumentTable.setTexture(coarse.gpuResourceID, index: 3)
      dispatchGrid(encoder: encoder, width: coarse.width, height: coarse.height)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }

    multigridCoarseSolve(encoder: encoder, level: coarsest)

    for level in stride(from: coarsest - 1, through: 0, by: -1) {
      let fine = mgPressure[level]
      encoder.setComputePipelineState(pipelines.mgProlong)
      argumentTable.setTexture(mgPressure[level + 1].gpuResourceID, index: 0)
      argumentTable.setTexture(fine.gpuResourceID, index: 1)
      dispatchGrid(encoder: encoder, width: fine.width, height: fine.height)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

      multigridSmooth(encoder: encoder, level: level, sweeps: Self.multigridPostSmooth)
    }
  }

  private func multigridSmooth(encoder: any MTL4ComputeCommandEncoder,
                               level: Int,
                               sweeps: Int) {
    let pressure = mgPressure[level]
    encoder.setComputePipelineState(pipelines.mgSmooth)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 1)
    let groups = MTLSize(width: (pressure.width + 15) / 16, height: (pressure.height + 15) / 16, depth: 1)
    let groupSize = MTLSize(width: 16, height: 16, depth: 1)
    for _ in 0..<sweeps {
      encoder.dispatchThreadgroups(threadgroupsPerGrid: groups, threadsPerThreadgroup: groupSize)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }

  private func multigridCoarseSolve(encoder: any MTL4ComputeCommandEncoder,
                                    level: Int) {
    let pipeline = pipelines.mgCoarseSolve
    encoder.setComputePipelineState(pipeline)
    argumentTable.setTexture(mgPressure[level].gpuResourceID, index: 0)
    argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(UInt32(Self.multigridCoarseSweeps)), index: 0)
    let threads = min(1024, pipeline.maxTotalThreadsPerThreadgroup)
    encoder.dispatchThreadgroups(threadgroupsPerGrid: MTLSize(width: 1, height: 1, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1))
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }
}

#endif
