//
//  NavierStokesRenderer+Grid.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 10/31/26.
//

#if !targetEnvironment(simulator)
import Metal
import os

extension NavierStokesRenderer {
  static func targetGridSize(drawableWidth: Int, drawableHeight: Int) -> (width: Int, height: Int) {
    let aspect = Double(max(drawableWidth, 1)) / Double(max(drawableHeight, 1))
    let budget = Double(simulationCellBudget)
    let align = Double(gridAlignment)
    func fit(_ v: Double) -> Int {
      let aligned = (v / align).rounded() * align
      return Int(min(max(aligned, Double(minGridDimension)), Double(maxGridDimension)))
    }
    return (fit(sqrt(budget * aspect)), fit(sqrt(budget / aspect)))
  }

  func ensureSimulationGrid(drawableWidth: Int, drawableHeight: Int) {
    let aspect = Float(max(drawableWidth, 1)) / Float(max(drawableHeight, 1))
    if abs(aspect - gridAspect) < gridAspect * 0.02 { return }
    gridAspect = aspect

    let target = Self.targetGridSize(drawableWidth: drawableWidth, drawableHeight: drawableHeight)
    if target.width == gridWidth && target.height == gridHeight { return }
    rebuildSimulationGrid(width: target.width, height: target.height)
  }

  private func rebuildSimulationGrid(width: Int, height: Int) {
    sharedEvent.wait(untilSignaledValue: frameNumber, timeoutMS: 1000)

    guard let textures = Self.createTextures(device: device, width: width, height: height) else {
      Self.logger.error("Failed to rebuild simulation grid at \(width)x\(height); keeping current grid")
      return
    }

    let oldTextures = allSimulationTextures
    let oldDye = dyeA
    let oldVelocity = velocityA

    gridWidth = width
    gridHeight = height
    applyTextures(textures)
    for tex in allSimulationTextures { residencySet.addAllocation(tex) }
    residencySet.commit()

    taaHistoryValid = false
    carryOverSimulation(dye: oldDye, velocity: oldVelocity)

    for tex in oldTextures { residencySet.removeAllocation(tex) }
    residencySet.commit()
    Self.logger.info("Simulation grid rebuilt at \(width)x\(height)")
  }

  func applyTextures(_ t: Textures) {
    velocityA = t.velocityA
    velocityB = t.velocityB
    pressure = t.pressure
    divergenceTexture = t.divergence
    dyeA = t.dyeA
    dyeB = t.dyeB
    dyeC = t.dyeC
    bloomA = t.bloomA
    bloomB = t.bloomB
    bloomMidA = t.bloomMidA
    bloomLoA = t.bloomLoA
    psiA = t.psiA
    psiB = t.psiB
    psiC = t.psiC
    u0 = t.u0
    mgPsi = t.mgPsi
    mgRHS = t.mgRHS
  }

  var allSimulationTextures: [MTLTexture] {
    [velocityA, velocityB, pressure, divergenceTexture,
     dyeA, dyeB, dyeC,
     bloomA, bloomB, bloomMidA, bloomLoA,
     psiA, psiB, psiC, u0] + mgPsi + mgRHS
  }
}

#endif
