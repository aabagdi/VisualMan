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
  static let renderBloomStrength: Float = 0.18
  static let renderCloudBillow: Float = 0.6
  static let renderCloudBillowScale: Float = 7.0
  static let renderCloudBillowRegrowTime: Float = 0.35
  static let renderCloudShadow: Float = 2.5
  static let renderCloudRelief: Float = 2.5
  static let renderCloudCavity: Float = 0.6
  static let renderCloudAmbient: Float = 0.55
  static let renderCloudSun: Float = 0.65
  static let renderCloudThickness: Float = 2.0
  static let renderCloudVortexLift: Float = 0.6
  static let renderCloudVortexPresence: Float = 0.25
  static let renderCloudVortexScale: Float = 0.006
  static let renderTechnicolorPrintDensity: Float = 3.0
  static let renderTechnicolorThinPrintDensity: Float = 2.2
  static let renderTechnicolorDepthStart: Float = 0.4
  static let renderTechnicolorDepthEnd: Float = 1.5
  static let renderTechnicolorSharpen: Float = 2.0
  static let renderTechnicolorThinDepth: Float = pow(
    renderTechnicolorThinPrintDensity / renderTechnicolorPrintDensity, 2 / renderTechnicolorSharpen)
  static let renderTechnicolorPresence: Float = 3.0
  static let renderTechnicolorNeutralReach: Float = 0.5
  static let renderTechnicolorLampGain: Float = 1.8
  static let renderTechnicolorMaxHeadroom: Float = 2.0
  static let renderTechnicolorHeadroomLamp: Float = 0.5
  static let renderTechnicolorMisregistrationShift: Float = 0.0014
  static let renderTechnicolorMisregistrationRotation: Float = 0.0005
  static let renderTechnicolorMisregistrationMagnification: Float = 0.0007
  static let renderTechnicolorGateWeave: Float = 0.005
  static let renderTechnicolorGateWeaveRotation: Float = 0.0011
  static let renderTechnicolorGateJump: Float = 0.0042
  static let renderTechnicolorGateJumpRate: Float = 12
  static let renderTechnicolorHalation: Float = 2.4
  static let renderTechnicolorHalationKnee: Float = 0.4
  static let renderTechnicolorGrain: Float = 0.10
  static let renderTechnicolorGrainCloud: Float = 0.09
  static let renderTechnicolorGrainCloudChroma: Float = 0.3
  static let renderTechnicolorGrainCloudSize: Float = 1.7
  static let renderTechnicolorGrainRate: Float = 24

  static let dyeVelocitySmoothing: Float = 1.0
  static let dyeDiffusionBase: Float = 0.0225
  static let dyeEdgeFadeCells: Float = 28
  static let dyeEdgeFadeRate: Float = 0.06

  static let dyeMapDivisor: Int = 2
  static let dyeMapStrayCells: Float = 0.5
  static let dyeMapStrayFraction: Float = 0.002
  static let dyeMapMinInterval: Int = 4
  static let dyeMapMaxInterval: Int = 24

  static let dyeDissipation: Float = 0.99
  static let advectionTimeScale: Float = 80.0

  static let velocityDissipation: Float = 0.997
  static let maxSpeed: Float = 32.0

  static let multigridCoarseCells: Int = 2048
  static let multigridPredictorCycles: Int = 2
  static let multigridFinalCycles: Int = 1
  static let multigridCoarseSweeps: Int = 24

  static let flowMapTraceStepCells: Float = 2.0
  static let flowMapTraceMaxSteps: Float = 8
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
  static let buoyancyStrength: Float = 0.06
  static let buoyancySettleSpeed: Float = 6.0
  static let vortexConfinement: Float = 0.5
  static let vortexConfinementLoudness: Float = 0.2
  static let vortexConfinementFloor: Float = 0.005
  static let vortexConfinementCap: Float = 0.4
  static let emitterClumping: Float = 0.5
  static let emitterClumpSize: Float = 0.028
  static let emitterClumpHue: Float = 1.0
  static let emitterClumpHueShift: Float = 0.33
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

  static let excitementWobbleGain: Float = 1.5
  static let transientFollowerSeconds: Float = 0.08
  static let burstDecaySeconds: Float = 0.18
  static let burstGain: Float = 1.6
  static let percussiveSpillGain: Float = 0.8
}

#endif
