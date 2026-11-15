//
//  NavierStokesRenderer+Bloom.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/15/26.
//

#if !targetEnvironment(simulator)
import Metal

extension NavierStokesRenderer {
  func runBloomPasses(encoder: any MTL4ComputeCommandEncoder,
                      bass: Float,
                      mid: Float) {
    bloomThresholdBlurH(encoder: encoder, dst: bloomB, size: Self.bloomSize,
                        bass: bass, mid: mid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    blurBloomV(encoder: encoder, src: bloomB, dst: bloomA, size: Self.bloomSize)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    bloomDownsample(encoder: encoder, src: bloomA, dst: bloomMidA, dstSize: Self.bloomSizeMid)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    bloomDownsample(encoder: encoder, src: bloomMidA, dst: bloomLoA, dstSize: Self.bloomSizeLo)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }

  func bloomThresholdBlurH(encoder: any MTL4ComputeCommandEncoder,
                           dst: MTLTexture,
                           size: Int,
                           bass: Float,
                           mid: Float) {
    encoder.setComputePipelineState(pipelines.bloomThresholdBlurH)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    let threshold: Float = max(0.50, 1.21 - bass * 0.57 - mid * 0.21)
    argumentTable.setAddress(writeUniform(threshold), index: 0)
    dispatchGrid(encoder: encoder, width: size, height: size)
  }

  func blurBloomV(encoder: any MTL4ComputeCommandEncoder,
                  src: MTLTexture,
                  dst: MTLTexture,
                  size: Int) {
    encoder.setComputePipelineState(pipelines.blurV)
    argumentTable.setTexture(src.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder, width: size, height: size)
  }

  func bloomDownsample(encoder: any MTL4ComputeCommandEncoder,
                       src: MTLTexture,
                       dst: MTLTexture,
                       dstSize: Int) {
    encoder.setComputePipelineState(pipelines.bloomDownsample)
    argumentTable.setTexture(src.gpuResourceID, index: 0)
    argumentTable.setTexture(dst.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder, width: dstSize, height: dstSize)
  }
}

#endif
