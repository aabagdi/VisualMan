//
//  NavierStokesRenderer+Film.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/17/26.
//

#if !targetEnvironment(simulator)
import Foundation
import Metal

extension NavierStokesRenderer {
  var technicolorGateWeave: SIMD4<Float> {
    let t = projectorTime
    let weave = 0.55 * sin(t * 1.9) + 0.30 * sin(t * 4.7 + 1.3) + 0.15 * sin(t * 11.3 + 0.7)
    let jump = 0.40 * sin(t * 2.6 + 2.1) + 0.35 * sin(t * 7.1 + 0.4) + 0.25 * sin(t * 17.9 + 4.2)
    let turn = 0.60 * sin(t * 1.3 + 0.9) + 0.40 * sin(t * 3.7 + 5.0)
    return SIMD4<Float>(weave * Self.renderTechnicolorGateWeave,
                        jump * Self.renderTechnicolorGateWeave,
                        turn * Self.renderTechnicolorGateWeaveRotation, 0)
  }

  func advanceGateJump(outWidth: Int, outHeight: Int) {
    var jump = gateJump
    let jumpIndex = Int(projectorTime * Self.renderTechnicolorGateJumpRate)
    if jumpIndex != gateJumpIndex {
      gateJumpIndex = jumpIndex
      let reach = Self.renderTechnicolorGateJump * Float(min(outWidth, outHeight))
      let side = Float.random(in: -1...1) * Float.random(in: 0...1)
      let lift = Float.random(in: -1...1) * Float.random(in: 0...1)
      jump = SIMD2<Float>((0.5 * reach * side).rounded(), (reach * lift).rounded())
    }
    gateStep = jump - gateJump
    gateJump = jump
  }

  func advanceGrain() {
    let shown = grainShift.lowHalf
    var shift = shown
    let index = Int(projectorTime * Self.renderTechnicolorGrainRate)
    if index != grainIndex {
      grainIndex = index
      shift = SIMD2<Float>(Float(Int.random(in: 0..<Self.technicolorGrainSize)),
                           Float(Int.random(in: 0..<Self.technicolorGrainSize)))
    }
    grainShift = SIMD4<Float>(lowHalf: shift, highHalf: shown)
  }

  static let technicolorHalation = SIMD4<Float>(
    renderTechnicolorHalation, renderTechnicolorHalationKnee, 0, 0)

  func runHalationPasses(encoder: any MTL4ComputeCommandEncoder, history: MTLTexture) {
    guard let exposure = taaExposure else { return }
    let width = (halationA.width + 15) & ~15
    let height = (halationA.height + 15) & ~15
    let coverage = SIMD2<Float>(Float(history.width) / Float(4 * exposure.width),
                                Float(history.height) / Float(4 * exposure.height))

    encoder.setComputePipelineState(pipelines.halationSource)
    argumentTable.setTexture(exposure.gpuResourceID, index: 0)
    argumentTable.setTexture(halationA.gpuResourceID, index: 1)
    argumentTable.setAddress(frameUniformsAddress, index: 0)
    argumentTable.setAddress(writeUniform(coverage), index: 1)
    dispatchGrid(encoder: encoder, width: width, height: height)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

    for _ in 0..<3 {
      encoder.setComputePipelineState(pipelines.blurH)
      argumentTable.setTexture(halationA.gpuResourceID, index: 0)
      argumentTable.setTexture(halationB.gpuResourceID, index: 1)
      dispatchGrid(encoder: encoder, width: width, height: height)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)

      encoder.setComputePipelineState(pipelines.blurV)
      argumentTable.setTexture(halationB.gpuResourceID, index: 0)
      argumentTable.setTexture(halationA.gpuResourceID, index: 1)
      dispatchGrid(encoder: encoder, width: width, height: height)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }
}

#endif
