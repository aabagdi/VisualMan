//
//  OscilloscopeVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct OscilloscopeVisualizerView: View {
  @State private var time: Float = 0
  @State private var smoothedBass: Float = 0
  @State private var smoothedMid: Float = 0
  @State private var smoothedHigh: Float = 0
  @State private var smoothedLevels = [128 of Float](repeating: 0.0)
  
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
    let maxAmplitude = size.height * 0.35
    let pointCount = smoothedLevels.count
    
    var path = Path()
    guard pointCount > 1 else { return path }
    
    let stepX = size.width / CGFloat(pointCount - 1)
    
    for i in 0..<pointCount {
      let x = CGFloat(i) * stepX
      let level = CGFloat(smoothedLevels[i])
      let sign: CGFloat = sin(CGFloat(i) * 0.3 + CGFloat(time) * 2.0) >= 0 ? 1.0 : -1.0
      let y = cy + level * maxAmplitude * sign
      
      if i == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        let prevX = CGFloat(i - 1) * stepX
        let prevLevel = CGFloat(smoothedLevels[i - 1])
        let prevSign: CGFloat = sin(CGFloat(i - 1) * 0.3 + CGFloat(time) * 2.0) >= 0 ? 1.0 : -1.0
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
        let gridOpacity = 0.06
        let gridSpacing: CGFloat = 30
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
        context.stroke(centerLine, with: .color(.green.opacity(0.3)), lineWidth: 1.0)
        
        let waveform = buildWaveformPath(size: size)
        
        let glowLayers: [(width: CGFloat, opacity: Double)] = [
          (12.0, 0.03),
          (8.0, 0.06),
          (5.0, 0.1),
          (3.0, 0.2),
          (1.5, 0.9)
        ]
        
        let audioEnergy = Double(smoothedBass + smoothedMid + smoothedHigh) / 3.0
        let brightness = 0.7 + audioEnergy * 0.3
        
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
      .onChange(of: timeline.date) {
        smoothedBass = smoothedBass * 0.5 + audioLevels.bassLevel * 0.5
        smoothedMid = smoothedMid * 0.6 + audioLevels.midLevel * 0.4
        smoothedHigh = smoothedHigh * 0.4 + audioLevels.highLevel * 0.6
        time += 0.016 * (1.0 + smoothedBass * 0.5)
        
        let newLevels = downsampledLevels()
        for i in 0..<smoothedLevels.count {
          smoothedLevels[i] = smoothedLevels[i] * 0.6 + newLevels[i] * 0.4
        }
      }
      .ignoresSafeArea()
    }
  }
}
