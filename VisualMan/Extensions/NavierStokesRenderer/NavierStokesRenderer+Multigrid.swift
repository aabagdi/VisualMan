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
    argumentTable.setTexture(mgPsi[0].gpuResourceID, index: 2)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    for _ in 0..<Self.multigridCycles {
      multigridVCycle(encoder: encoder, neumann: true)
    }

    gradientSubtract(encoder: encoder, pressure: mgPsi[0])
  }

  func projectStreamfunction(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(pipelines.vorticityRHS)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(mgRHS[0].gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    for _ in 0..<Self.multigridCycles {
      multigridVCycle(encoder: encoder, neumann: false)
    }

    encoder.setComputePipelineState(pipelines.curlPsi)
    argumentTable.setTexture(mgPsi[0].gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
  }

  private func multigridVCycle(encoder: any MTL4ComputeCommandEncoder, neumann: Bool) {
    let coarsest = mgPsi.count - 1
    let boundaryFlag = writeUniform(UInt32(neumann ? 1 : 0))

    for level in 0..<coarsest {
      multigridSmooth(encoder: encoder, level: level, sweeps: Self.multigridPreSmooth,
                      boundaryFlag: boundaryFlag)

      let coarse = mgPsi[level + 1]
      encoder.setComputePipelineState(pipelines.mgRestrict)
      argumentTable.setTexture(mgPsi[level].gpuResourceID, index: 0)
      argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 1)
      argumentTable.setTexture(mgRHS[level + 1].gpuResourceID, index: 2)
      argumentTable.setTexture(coarse.gpuResourceID, index: 3)
      argumentTable.setAddress(boundaryFlag, index: 0)
      dispatchGrid(encoder: encoder, width: coarse.width, height: coarse.height)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }

    multigridCoarseSolve(encoder: encoder, level: coarsest, boundaryFlag: boundaryFlag)

    for level in stride(from: coarsest - 1, through: 0, by: -1) {
      let fine = mgPsi[level]
      encoder.setComputePipelineState(pipelines.mgProlong)
      argumentTable.setTexture(mgPsi[level + 1].gpuResourceID, index: 0)
      argumentTable.setTexture(fine.gpuResourceID, index: 1)
      dispatchGrid(encoder: encoder, width: fine.width, height: fine.height)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

      multigridSmooth(encoder: encoder, level: level, sweeps: Self.multigridPostSmooth,
                      boundaryFlag: boundaryFlag)
    }
  }

  private func multigridSmooth(encoder: any MTL4ComputeCommandEncoder,
                               level: Int,
                               sweeps: Int,
                               boundaryFlag: MTLGPUAddress) {
    let psi = mgPsi[level]
    encoder.setComputePipelineState(pipelines.mgSmooth)
    argumentTable.setTexture(psi.gpuResourceID, index: 0)
    argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 1)
    argumentTable.setAddress(boundaryFlag, index: 0)
    for _ in 0..<sweeps {
      dispatchGrid(encoder: encoder, width: psi.width, height: psi.height)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }

  private func multigridCoarseSolve(encoder: any MTL4ComputeCommandEncoder,
                                    level: Int,
                                    boundaryFlag: MTLGPUAddress) {
    let pipeline = pipelines.mgCoarseSolve
    encoder.setComputePipelineState(pipeline)
    argumentTable.setTexture(mgPsi[level].gpuResourceID, index: 0)
    argumentTable.setTexture(mgRHS[level].gpuResourceID, index: 1)
    argumentTable.setAddress(boundaryFlag, index: 0)
    argumentTable.setAddress(writeUniform(UInt32(Self.multigridCoarseSweeps)), index: 1)
    let threads = min(1024, pipeline.maxTotalThreadsPerThreadgroup)
    encoder.dispatchThreadgroups(threadgroupsPerGrid: MTLSize(width: 1, height: 1, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1))
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }
}

#endif
