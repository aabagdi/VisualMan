//
//  NavierStokesRenderer+Tuning.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 10/31/26.
//

#if !targetEnvironment(simulator)
import Foundation

extension NavierStokesRenderer {
  static let renderShading: Float = 0.6
  static let renderDetail: Float = 0.3
  static let renderJitter: Float = 0.0005
  static let renderThinFade: Float = 0.18

  static let dyeDiffusionBase: Float = 0.045
  static let dyeEdgeFadeCells: Float = 28
  static let dyeEdgeFadeRate: Float = 0.06

  static let dyeDissipation: Float = 0.99
  static let advectionTimeScale: Float = 80.0

  static let velocityDissipation: Float = 0.997
  static let velocityViscosity: Float = 0.2
  static let viscosityAudioReduction: Float = 0.05
  static let maxSpeed: Float = 32.0
  static let vorticityConfinementScale: Float = 0.10
  
  static let multigridCoarseCells: Int = 2048
  static let multigridCycles: Int = 2
  static let multigridPreSmooth: Int = 1
  static let multigridPostSmooth: Int = 1
  static let multigridCoarseSweeps: Int = 24

  static let flowMapStretchThreshold: Float = 0.35
  static let reinitStretchFraction: Float = 0.002
  static let reinitMinInterval: Int = 4
  static let reinitMaxInterval: Int = 12

  static let bassJetSpeed: Float = 3.0
  static let bassJetSpeedRange: Float = 10.0
  static let midJetSpeed: Float = 2.0
  static let midJetSpeedRange: Float = 8.0
  static let highJetSpeed: Float = 3.0
  static let highJetSpeedRange: Float = 9.0
  static let bassJetRadius: Float = 0.055
  static let midJetRadius: Float = 0.036
  static let highJetRadius: Float = 0.036
  static let highBandGain: Float = 1.4
  static let buoyancyStrength: Float = 0.03
  static let buoyancySettleSpeed: Float = 6.0
  static let bassGasWeight: Float = 0.6
  static let midGasWeight: Float = -0.3
  static let highGasWeight: Float = -1.2

  static let dyeInjectionScale: Float = 0.5
  static let dynamicsEnvelopeSeconds: Float = 2.0
  static let dynamicsMin: Float = 0.3
  static let dynamicsMax: Float = 3.5
  static let dynamicsSpeedExponent: Float = 1.0
  static let dynamicsVolumeExponent: Float = 1.0
  static let dynamicsFloor: Float = 0.1

  static let excitementViscosityReduction: Float = 0.75
  static let excitementConfinementGain: Float = 2.0
  static let excitementWobbleGain: Float = 1.5
  static let transientFollowerSeconds: Float = 0.08
  static let burstDecaySeconds: Float = 0.18
  static let burstGain: Float = 1.6
  static let percussiveSpillGain: Float = 0.8
}

#endif
