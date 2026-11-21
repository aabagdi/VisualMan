//
//  AbstractExpressionismRenderer+MixboxSelfTest.swift
//  VisualMan
//
//  Created on 11/4/26.
//

#if !targetEnvironment(simulator)
import Metal
import os
import simd

extension AbstractExpressionismRenderer {
  private struct SelfTestCase {
    let name: String
    let a: Int, b: Int
    let expected: SIMD3<Float>
  }

  private static let selfTestCases: [SelfTestCase] = [
    SelfTestCase(name: "Ultramarine + Cadmium Yellow", a: 6, b: 0, expected: SIMD3(59, 123, 50)),
    SelfTestCase(name: "Quinacridone Magenta + Cadmium Yellow", a: 4, b: 0, expected: SIMD3(192, 93, 37)),
    SelfTestCase(name: "Cadmium Red + Cadmium Yellow", a: 3, b: 0, expected: SIMD3(255, 117, 28)),
  ]
  private static let selfTestTolerance: Float = 6

  private static let selfTestSlots = 16

  func makeMixboxSelfTestBuffer() -> MTLBuffer? {
    device.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride * Self.selfTestSlots,
                      options: .storageModeShared)
  }

  func encodeMixboxSelfTest(encoder: any MTL4ComputeCommandEncoder, results: MTLBuffer) {
    guard let lut = mixboxLUT else { return }
    var inputs = [SIMD4<Float>]()
    for c in Self.selfTestCases {
      let pa = Self.mixboxPigments[c.a].linearRgb, pb = Self.mixboxPigments[c.b].linearRgb
      inputs.append(SIMD4(pa.x, pa.y, pa.z, 0))
      inputs.append(SIMD4(pb.x, pb.y, pb.z, 0))
    }
    encoder.setComputePipelineState(mixboxSelfTestPipeline)
    argumentTable.setTexture(lut.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniformArray(inputs), index: 0)
    argumentTable.setAddress(results.gpuAddress, index: 1)
    let n = Self.selfTestSlots
    encoder.dispatchThreads(threadsPerGrid: MTLSize(width: n, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: n, height: 1, depth: 1))
  }

  func reportMixboxSelfTest(results: MTLBuffer) {
    let ptr = results.contents().bindMemory(to: SIMD4<Float>.self,
                                            capacity: Self.selfTestSlots)
    var failures = 0
    for (i, c) in Self.selfTestCases.enumerated() {
      let got = SIMD3(ptr[i].x, ptr[i].y, ptr[i].z) * 255
      let err = simd_reduce_max(abs(got - c.expected))
      let line = String(format: "%@: got (%.0f, %.0f, %.0f) expected (%.0f, %.0f, %.0f) max err %.1f",
                        c.name, got.x, got.y, got.z,
                        c.expected.x, c.expected.y, c.expected.z, err)
      if err > Self.selfTestTolerance {
        failures += 1
        Self.logger.error("Mixbox self-test FAILED \(line, privacy: .public)")
      } else {
        Self.logger.notice("Mixbox self-test ok \(line, privacy: .public)")
      }
    }
    if failures == 0 {
      Self.logger.notice("Mixbox self-test PASSED: LUT orientation and colour space are correct")
    } else {
      func v(_ i: Int, _ scale: Float) -> String {
        String(format: "(%.3f, %.3f, %.3f)", ptr[i].x * scale, ptr[i].y * scale, ptr[i].z * scale)
      }
      let diag = "input0 linear \(v(3, 1)); LUT(0,0) \(v(4, 255)) expect (124,67,63); "
        + "LUT(326,128) \(v(5, 255)) expect (220,3,31); c(input0) \(v(6, 1)); "
        + "input0 round-trip sRGB \(v(7, 255)) expect (25,0,89)"
      Self.logger.error("Mixbox self-test diagnostics: \(diag, privacy: .public)")
      func v4(_ i: Int) -> String {
        String(format: "(%.3f, %.3f, %.3f, %.3f)", ptr[i].x, ptr[i].y, ptr[i].z, ptr[i].w)
      }
      let lookup = "srgb \(v4(8)) expect (0.098, 0, 0.349); xyz,iz \(v4(9)) expect (6.17, 0, 21.99, 21); "
        + "uv0,uv1 px \(v4(10)) expect (326.67, 128.5, 390.67, 128.5); "
        + "sample uv0 \(v(11, 255)) expect ~(218,3,33); sample uv1 \(v(12, 255)) expect ~(216,2,36); "
        + "probe texel \(v(13, 255)) expect (124,67,63); lut size \(v4(14))"
      Self.logger.error("Mixbox lookup trace: \(lookup, privacy: .public)")
    }
  }
}

#endif
