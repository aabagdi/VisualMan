//
//  ThreeDBarsVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/1/25.
//

import SwiftUI
import RealityKit
import UIKit

struct ThreeDBarsVisualizerView: View {
  let visualizerBars: [32 of Float]
  @State private var model = ThreeDBarsVisualizerViewModel()

  var body: some View {
    ThreeDBarsARViewRepresentable(
      visualizerBars: visualizerBars,
      model: model
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
    .onAppear {
      model.startSmoothing()
    }
    .onDisappear {
      model.stopSmoothing()
    }
    .onChange(of: visualizerBars) { _, newValues in
      model.targetValues = newValues
    }
  }
}

private struct ThreeDBarsARViewRepresentable: UIViewRepresentable {
  let visualizerBars: [32 of Float]
  let model: ThreeDBarsVisualizerView.ThreeDBarsVisualizerViewModel
  @Environment(VisualizerSnapshotter.self) private var snapshotter

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> ARView {
    let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    arView.environment.background = .color(.black)
    arView.backgroundColor = .black

    let camera = PerspectiveCamera()
    camera.camera.fieldOfViewInDegrees = 60
    let cameraAnchor = AnchorEntity(world: .zero)
    cameraAnchor.addChild(camera)
    arView.scene.addAnchor(cameraAnchor)

    let rootAnchor = AnchorEntity(world: .zero)
    let sharedMesh = MeshResource.generateBox(size: [0.2, 1.0, 0.2])

    var entities: [Entity] = []
    for index in visualizerBars.indices {
      let barContainer = Entity()

      var material = PhysicallyBasedMaterial()
      material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: barColor(index: index,
                                                                            totalBars: visualizerBars.count))
      let barEntity = ModelEntity(mesh: sharedMesh, materials: [material])
      barEntity.position.y = 0.5
      barContainer.addChild(barEntity)

      let totalWidth: Float = 8.0
      let spacing = totalWidth / Float(visualizerBars.count - 1)
      let xPosition = -totalWidth / 2 + Float(index) * spacing
      barContainer.position = [xPosition, 0, 0]

      rootAnchor.addChild(barContainer)
      entities.append(barContainer)
    }
    model.barEntities = entities
    arView.scene.addAnchor(rootAnchor)

    context.coordinator.cameraEntity = camera
    context.coordinator.arView = arView
    context.coordinator.snapshotter = snapshotter
    context.coordinator.updateCameraPosition()

    let pan = UIPanGestureRecognizer(target: context.coordinator,
                                     action: #selector(Coordinator.handlePan(_:)))
    let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePinch(_:)))
    arView.addGestureRecognizer(pan)
    arView.addGestureRecognizer(pinch)

    snapshotter.snapshotOverride = { [weak arView] in
      guard let arView else { return nil }
      return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
        arView.snapshot(saveToHDR: false) { image in
          continuation.resume(returning: image)
        }
      }
    }

    return arView
  }

  func updateUIView(_ uiView: ARView, context: Context) {}

  static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
    coordinator.snapshotter?.snapshotOverride = nil
  }

  private func barColor(index: Int, totalBars: Int) -> UIColor {
    UIColor(BarView.barColor(index: index, totalBars: totalBars))
  }

  @MainActor
  final class Coordinator: NSObject {
    weak var arView: ARView?
    weak var cameraEntity: PerspectiveCamera?
    weak var snapshotter: VisualizerSnapshotter?

    private var rotationAngle: Float = 0
    private var verticalAngle: Float = 0
    private var cameraDistance: Float = 20.0
    private var pinchStartDistance: Float = 20.0

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
      switch gesture.state {
      case .changed:
        let translation = gesture.translation(in: gesture.view)
        let sensitivity: Float = 0.0003
        rotationAngle += Float(translation.x) * sensitivity
        verticalAngle -= Float(translation.y) * sensitivity
        verticalAngle = max(-1.2, min(1.2, verticalAngle))
        updateCameraPosition()
      default:
        break
      }
    }

    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
      switch gesture.state {
      case .began:
        pinchStartDistance = cameraDistance
      case .changed:
        let zoomSensitivity: Float = 0.5
        let targetDistance = pinchStartDistance / Float(gesture.scale)
        cameraDistance += (targetDistance - cameraDistance) * zoomSensitivity
        cameraDistance = max(10.0, min(30.0, cameraDistance))
        updateCameraPosition()
      default:
        break
      }
    }

    func updateCameraPosition() {
      guard let camera = cameraEntity else { return }

      let x = sin(rotationAngle) * cos(verticalAngle) * cameraDistance
      let y = sin(verticalAngle) * cameraDistance + 5.0
      let z = cos(rotationAngle) * cos(verticalAngle) * cameraDistance

      camera.position = [x, y, z]
      camera.look(at: [0, 0, 0], from: camera.position, relativeTo: nil)
    }
  }
}
