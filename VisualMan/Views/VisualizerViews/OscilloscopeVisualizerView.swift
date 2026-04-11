//
//  OscilloscopeVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct OscilloscopeVisualizerView: View {
  private enum Constants {
    static let levelSmoothing: Float = 0.6
    static let gridOpacity: Double = 0.06
    static let gridSpacing: CGFloat = 30
    static let centerLineOpacity: Double = 0.3
    static let maxAmplitudeFraction: CGFloat = 0.35
  }
  
  @State private var audio = SmoothedAudio()
  @State private var smoothedLevels: [128 of Float] = .init(repeating: 0.0)
  
  let audioLevels: [1024 of Float]
  
  private func downsampledLevels() -> [128 of Float] {
    var result = [128 of Float](repeating: 0.0)
    let binsPerPoint = 1024 / 128
    for i in 0..<128 {
      let start = i * binsPerPoint
      var maxVal: Float = 0
      for j in start..<(start + binsPerPoint) {
        maxVal = max(maxVal, audioLevels[j])
      }
      result[i] = maxVal
    }
    return result
  }
  
  private func buildWaveformPath(size: CGSize) -> Path {
    let cy = size.height / 2
    let maxAmplitude = size.height * Constants.maxAmplitudeFraction
    let pointCount = smoothedLevels.count
    
    var path = Path()
    guard pointCount > 1 else { return path }
    
    let stepX = size.width / CGFloat(pointCount - 1)
    
    for i in 0..<pointCount {
      let x = CGFloat(i) * stepX
      let level = CGFloat(smoothedLevels[i])
      let sign: CGFloat = sin(CGFloat(i) * 0.3 + CGFloat(audio.time) * 2.0) >= 0 ? 1.0 : -1.0
      let y = cy + level * maxAmplitude * sign
      
      if i == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        let prevX = CGFloat(i - 1) * stepX
        let prevLevel = CGFloat(smoothedLevels[i - 1])
        let prevSign: CGFloat = sin(CGFloat(i - 1) * 0.3 + CGFloat(audio.time) * 2.0) >= 0 ? 1.0 : -1.0
        let prevY = cy + prevLevel * maxAmplitude * prevSign
        let midX = (prevX + x) / 2
        let midY = (prevY + y) / 2
        path.addQuadCurve(to: CGPoint(x: midX, y: midY),
                          control: CGPoint(x: prevX, y: prevY))
        if i == pointCount - 1 {
          path.addLine(to: CGPoint(x: x, y: y))
        }
      }
    }
    return path
  }
  
  var body: some View {
    TimelineView(.animation) { timeline in
      Canvas { context, size in
        let gridOpacity = Constants.gridOpacity
        let gridSpacing = Constants.gridSpacing
        for x in stride(from: CGFloat(0), through: size.width, by: gridSpacing) {
          var line = Path()
          line.move(to: CGPoint(x: x, y: 0))
          line.addLine(to: CGPoint(x: x, y: size.height))
          context.stroke(line, with: .color(.green.opacity(gridOpacity)), lineWidth: 0.5)
        }
        for y in stride(from: CGFloat(0), through: size.height, by: gridSpacing) {
          var line = Path()
          line.move(to: CGPoint(x: 0, y: y))
          line.addLine(to: CGPoint(x: size.width, y: y))
          context.stroke(line, with: .color(.green.opacity(gridOpacity)), lineWidth: 0.5)
        }
        
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: 0, y: size.height / 2))
        centerLine.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(centerLine, with: .color(.green.opacity(Constants.centerLineOpacity)), lineWidth: 1.0)
        
        let waveform = buildWaveformPath(size: size)
        
        let glowLayers: [(width: CGFloat, opacity: Double)] = [
          (12.0, 0.03),
          (8.0, 0.06),
          (5.0, 0.1),
          (3.0, 0.2),
          (1.5, 0.9)
        ]
        
        let audioEnergy = Double(audio.bass + audio.mid + audio.high) / 3.0
        let brightness = min(0.7 + audioEnergy * 0.3, 1.0)
        
        for layer in glowLayers {
          context.stroke(
            waveform,
            with: .color(Color(hue: 0.33,
                              saturation: 0.8,
                              brightness: brightness,
                              opacity: layer.opacity)),
            lineWidth: layer.width
          )
        }
      }
      .background(Color(red: 0.02, green: 0.03, blue: 0.02))
      .onChange(of: timeline.date) { oldValue, newValue in
        let dt = min(Float(newValue.timeIntervalSince(oldValue)), 1.0 / 30.0)
        audio.update(from: audioLevels, dt: dt)
        
        let newLevels = downsampledLevels()
        for i in 0..<smoothedLevels.count {
          let smooth = Constants.levelSmoothing
          smoothedLevels[i] = smoothedLevels[i] * smooth + newLevels[i] * (1.0 - smooth)
        }
      }
      .ignoresSafeArea()
    }
  }
}
