//
//  ThreeDBarsVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/1/25.
//

import SwiftUI
import RealityKit

struct ThreeDBarsVisualizerView: View {
  let visualizerBars: [Float]
  @State private var model = ThreeDBarsVisualizerViewModel()
  @State private var cameraEntity: PerspectiveCamera?
  @State private var rotationAngle: Float = 0
  @State private var verticalAngle: Float = 0
  @State private var cameraDistance: Float = 20.0
  
  var body: some View {
    RealityView { content in
      let camera = PerspectiveCamera()
      camera.camera.fieldOfViewInDegrees = 60
      cameraEntity = camera
      content.add(camera)
      
      updateCameraPosition()
      
      let root = Entity()
      root.position = [0.0, 0.0, 0.0]
      
      for (index, _) in visualizerBars.enumerated() {
        let barContainer = Entity()
        barContainer.name = "bar_\(index)"
        
        let barMesh = MeshResource.generateBox(size: [0.2, 1.0, 0.2])
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: barColor(index: index, totalBars: visualizerBars.count))
        let barEntity = ModelEntity(mesh: barMesh, materials: [material])
        
        barEntity.position.y = 0.5
        
        barContainer.addChild(barEntity)
        
        let totalWidth: Float = 8.0
        let spacing = totalWidth / Float(visualizerBars.count - 1)
        let xPosition = -totalWidth / 2 + Float(index) * spacing
        barContainer.position = [xPosition, 0, 0]
        
        root.addChild(barContainer)
      }
      content.add(root)
    } update: { content in
      guard let root = content.entities.first(where: { !($0 is PerspectiveCamera) }) else { return }
      
      for (index, smoothedValue) in model.smoothedValues.enumerated() {
        guard let barContainer = root.findEntity(named: "bar_\(index)") else { continue }
        barContainer.scale = [1.0, smoothedValue, 1.0]
      }
    }
    .background {
      Color.black
    }
    .gesture(
      DragGesture()
        .onChanged { value in
          let sensitivity: Float = 0.0003
          rotationAngle += Float(value.translation.width) * sensitivity
          verticalAngle -= Float(value.translation.height) * sensitivity
          verticalAngle = max(-1.2, min(1.2, verticalAngle))
          updateCameraPosition()
        }
    )
    .gesture(
      MagnificationGesture()
        .onChanged { value in
          let zoomSensitivity: Float = 0.5
          let targetDistance = cameraDistance / Float(value)
          cameraDistance = cameraDistance + (targetDistance - cameraDistance) * zoomSensitivity
          cameraDistance = max(10.0, min(30.0, cameraDistance))
          updateCameraPosition()
        }
    )
    .onAppear {
      model.startSmoothing(targetValues: visualizerBars)
    }
    .onDisappear {
      model.stopSmoothing()
    }
    .onChange(of: visualizerBars) { _, newValues in
      model.startSmoothing(targetValues: newValues)
    }
  }
  
  private func updateCameraPosition() {
    guard let camera = cameraEntity else { return }
    
    let x = sin(rotationAngle) * cos(verticalAngle) * cameraDistance
    let y = sin(verticalAngle) * cameraDistance + 5.0
    let z = cos(rotationAngle) * cos(verticalAngle) * cameraDistance
    
    camera.position = [x, y, z]
    camera.look(at: [0, 0, 0], from: camera.position, relativeTo: nil)
  }
  
  private func barColor(index: Int, totalBars: Int) -> UIColor {
    let position = Float(index) / Float(totalBars)
    
    if position < 0.33 {
      let t = position / 0.33
      return UIColor(
        red: Double(t),
        green: 1.0,
        blue: 0.0,
        alpha: 1.0
      )
    } else if position < 0.66 {
      let t = (position - 0.33) / 0.33
      return UIColor(
        red: 1.0,
        green: Double(1.0 - t * 0.5),
        blue: 0.0,
        alpha: 1.0
      )
    } else {
      let t = (position - 0.66) / 0.34
      return UIColor(
        red: 1.0,
        green: Double(0.5 - t * 0.5),
        blue: 0.0,
        alpha: 1.0
      )
    }
  }
}
