//
//  LiquidLightRenderer+Uniforms.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/5/26.
//

#if !targetEnvironment(simulator)
import simd

struct LiquidLightDrops {
  var d0: SIMD4<Float>
  var d1: SIMD4<Float>
  var d2: SIMD4<Float>
  var d3: SIMD4<Float>
}

struct LiquidLightDropState {
  var s0: SIMD4<Float>
  var s1: SIMD4<Float>
  var s2: SIMD4<Float>
  var s3: SIMD4<Float>
}

struct LiquidLightPlate {
  var dyeA: SIMD4<Float>
  var dyeB: SIMD4<Float>
  var dyeC: SIMD4<Float>
  var dyeD: SIMD4<Float>
  var water: SIMD4<Float>
  var lamp: SIMD4<Float>
}

struct LiquidLightParams {
  var time: Float
  var bass: Float
  var mid: Float
  var high: Float
  var simSize: SIMD2<Float>
  var eps: Float
  var apertureRadius: Float
  var plate: LiquidLightPlate
  var ripples: LiquidLightDrops
}

struct LiquidSeedParams {
  var simSize: SIMD2<Float>
  var eps: Float
  var threshold: Float
}

struct LiquidAdvectParams {
  var simSize: SIMD2<Float>
  var tilt: SIMD2<Float>
  var frames: Float
  var time: Float
  var swirl: Float
  var press: Float
  var eps: Float
  var pad0: Float = 0
  var pad1: Float = 0
  var pad2: Float = 0
  var drops: LiquidLightDrops
  var dropState: LiquidLightDropState
}

struct LiquidRelaxParams {
  var dt: Float
  var mobility: Float
  var eps2: Float
  var acMobility: Float
}

struct LiquidProbeParams {
  var simSize: SIMD2<Float>
  var center: SIMD2<Float>
  var offset: SIMD2<Float>
  var pad: SIMD2<Float> = .zero
}

struct LiquidReduceParams {
  var tileCount: UInt32
  var invCellCount: Float
}

struct BlurParams {
  var innerRadius: Float
  var outerRadius: Float
  var maxBlurRadius: Float
  var bass: Float
  var mid: Float
  var bloomRadius: Float
  var bloomStrength: Float
}

struct FeedbackParams {
  var dt: Float
  var time: Float
  var bass: Float
  var historyValid: UInt32
}

#endif
