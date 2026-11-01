//
//  ThreeDBarsVisualizerViewModel.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/1/25.
//

import Foundation
import QuartzCore
import RealityKit
import SwiftUI

extension ThreeDBarsVisualizerView {
  @MainActor
  final class ThreeDBarsVisualizerViewModel {
    var targetValues: [32 of Float] = .init(repeating: 0.0)
    var barEntities: [Entity] = []

    private var smoothedValues: [32 of Float] = .init(repeating: minimumBarScale)
    private var lastFrameTime: CFTimeInterval = 0
    private var displayLinkStream: DisplayLinkStream?
    private var smoothingTask: Task<Void, Never>?

    private let attackTime: Float = 0.04
    private let releaseTime: Float = 0.12

    private static let minimumBarScale: Float = 0.01

    private var cameraEntity: Entity?
    private var rotationAngle: Float = 0
    private var verticalAngle: Float = 0
    private var cameraDistance: Float = 20.0
    private var pinchStartDistance: Float?

    func makeScene(barCount: Int) async -> Entity {
      let root = Entity()

      var cameraComponent = PerspectiveCameraComponent()
      cameraComponent.fieldOfViewInDegrees = 60
      let camera = Entity()
      camera.components.set(cameraComponent)
      root.addChild(camera)
      cameraEntity = camera

      let environmentLight = await Self.makeEnvironmentLight()
      if let environmentLight {
        root.components.set(ImageBasedLightComponent(source: .single(environmentLight)))
      }

      let sharedMesh = MeshResource.generateBox(size: [0.2, 1.0, 0.2])
      let totalWidth: Float = 8.0
      let spacing = totalWidth / Float(barCount - 1)

      var entities: [Entity] = []
      entities.reserveCapacity(barCount)

      for index in 0..<barCount {
        let barColor = UIColor(BarView.barColor(index: index, totalBars: barCount))

        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: barColor)
        material.roughness = 0.4
        material.metallic = 0.0
        material.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: barColor)
        material.emissiveIntensity = 0.5

        let barEntity = ModelEntity(mesh: sharedMesh, materials: [material])
        barEntity.position.y = 0.5
        if environmentLight != nil {
          barEntity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        }

        let barContainer = Entity()
        barContainer.addChild(barEntity)
        barContainer.position = [-totalWidth / 2 + Float(index) * spacing, 0, 0]

        root.addChild(barContainer)
        entities.append(barContainer)
      }

      barEntities = entities
      updateCameraPosition()
      return root
    }

    private static func makeEnvironmentLight() async -> EnvironmentResource? {
      let width = 64
      let height = 32
      let colorSpace = CGColorSpaceCreateDeviceRGB()

      guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
            let gradient = CGGradient(colorsSpace: colorSpace,
                                      colors: [UIColor(white: 1.00, alpha: 1).cgColor,
                                               UIColor(white: 0.62, alpha: 1).cgColor,
                                               UIColor(white: 0.25, alpha: 1).cgColor] as CFArray,
                                      locations: [0.0, 0.55, 1.0])
      else { return nil }

      context.drawLinearGradient(gradient,
                                 start: CGPoint(x: 0, y: height),
                                 end: CGPoint(x: 0, y: 0),
                                 options: [])

      guard let image = context.makeImage() else { return nil }

      if #available(iOS 27.0, *) {
        let options = EnvironmentResource.CreateOptions(skyboxMode: .preserve)
        return try? await EnvironmentResource(equirectangular: image, options: options)
      } else {
        return try? await EnvironmentResource(equirectangular: image)
      }
    }

    func orbit(translation: CGSize) {
      let sensitivity: Float = 0.0003
      rotationAngle += Float(translation.width) * sensitivity
      verticalAngle -= Float(translation.height) * sensitivity
      verticalAngle = max(-1.2, min(1.2, verticalAngle))
      updateCameraPosition()
    }

    func zoom(magnification: CGFloat) {
      let startDistance = pinchStartDistance ?? cameraDistance
      pinchStartDistance = startDistance

      let zoomSensitivity: Float = 0.5
      let targetDistance = startDistance / Float(magnification)
      cameraDistance += (targetDistance - cameraDistance) * zoomSensitivity
      cameraDistance = max(10.0, min(30.0, cameraDistance))
      updateCameraPosition()
    }

    func endZoom() {
      pinchStartDistance = nil
    }

    private func updateCameraPosition() {
      guard let cameraEntity else { return }

      let x = sin(rotationAngle) * cos(verticalAngle) * cameraDistance
      let y = sin(verticalAngle) * cameraDistance + 5.0
      let z = cos(rotationAngle) * cos(verticalAngle) * cameraDistance

      cameraEntity.look(at: [0, 0, 0], from: [x, y, z], relativeTo: nil)
    }

    func startSmoothing() {
      guard smoothingTask == nil else { return }
      lastFrameTime = CACurrentMediaTime()
      let stream = DisplayLinkStream()
      displayLinkStream = stream
      smoothingTask = Task { [weak self] in
        defer { self?.smoothingTask = nil }
        for await _ in stream.frames {
          guard !Task.isCancelled else { break }
          self?.updateSmoothedValues()
        }
      }
    }

    func stopSmoothing() {
      smoothingTask?.cancel()
      smoothingTask = nil
      displayLinkStream?.stop()
      displayLinkStream = nil
    }

    private func updateSmoothedValues() {
      let now = CACurrentMediaTime()
      let dt = min(0.1, max(1.0 / 240.0, Float(now - lastFrameTime)))
      lastFrameTime = now

      let entities = barEntities
      for index in 0..<min(targetValues.count, smoothedValues.count) {
        let targetHeight = max(Self.minimumBarScale, targetValues[index] * 10)

        let timeConstant = targetHeight > smoothedValues[index] ? attackTime : releaseTime
        let factor = 1.0 - exp(-dt / timeConstant)

        smoothedValues[index] += (targetHeight - smoothedValues[index]) * factor

        if index < entities.count {
          entities[index].scale = [1.0, max(Self.minimumBarScale, smoothedValues[index]), 1.0]
        }
      }
    }
  }
}
