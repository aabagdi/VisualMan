//
//  OscilloscopeVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct OscilloscopeVisualizerView: View {
  private enum Constants {
    static let attackSmoothing: Float = 0.55
    static let releaseSmoothing: Float = 0.75
    static let spatialSmoothingPasses = 3
    static let decayFactor: Float = 0.96
    static let decayThreshold: Float = 0.0005
    static let silenceThreshold: Float = 0.0001
    static let gridOpacity: Double = 0.15
    static let gridSpacing: CGFloat = 30
    static let centerLineOpacity: Double = 0.3
    static let maxAmplitudeFraction: CGFloat = 0.4
    static let displayPointCount = 256
    static let crtCurvature: Float = 0.15
    static let crtScanlineIntensity: Float = 0.3
    static let crtVignetteStrength: Float = 0.4
    static let phosphorRetention: Float = 0.75
  }

  @State private var audio = SmoothedAudio()
  @State private var smoothedWaveform: [Float] = .init(repeating: 0.0, count: Constants.displayPointCount)
  @State private var phosphorTrail: [Float] = .init(repeating: 0.0, count: Constants.displayPointCount)
  @State private var downsampleBuffer: [Float] = .init(repeating: 0.0, count: Constants.displayPointCount)

  let audioLevels: [1024 of Float]
  let waveform: [1024 of Float]

  private func downsampleWaveform(into buffer: inout [Float]) {
    let n = Constants.displayPointCount
    let samplesPerPoint = 1024 / n
    for i in 0..<n {
      let start = i * samplesPerPoint
      var sum: Float = 0
      for j in start..<(start + samplesPerPoint) {
        sum += waveform[j]
      }
      buffer[i] = sum / Float(samplesPerPoint)
    }

    for _ in 0..<Constants.spatialSmoothingPasses {
      let prev = buffer
      for i in 1..<(n - 1) {
        buffer[i] = prev[i - 1] * 0.25 + prev[i] * 0.5 + prev[i + 1] * 0.25
      }
    }
  }

  private func buildWaveformPath(from data: [Float], size: CGSize) -> Path {
    let cy = size.height / 2
    let maxAmplitude = size.height * Constants.maxAmplitudeFraction
    let pointCount = Constants.displayPointCount

    var path = Path()
    guard pointCount > 1 else { return path }

    let stepX = size.width / CGFloat(pointCount - 1)

    for i in 0..<pointCount {
      let x = CGFloat(i) * stepX
      let y = cy - CGFloat(data[i]) * maxAmplitude

      if i == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        let prevX = CGFloat(i - 1) * stepX
        let prevY = cy - CGFloat(data[i - 1]) * maxAmplitude
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
        context.fill(
          Path(CGRect(origin: .zero, size: size)),
          with: .color(Color(red: 0.02, green: 0.03, blue: 0.02))
        )

        let gridOpacity = Constants.gridOpacity
        let gridSpacing = Constants.gridSpacing
        let centerX = size.width / 2
        let centerY = size.height / 2

        for x in stride(from: centerX, through: size.width, by: gridSpacing) {
          var line = Path()
          line.move(to: CGPoint(x: x, y: 0))
          line.addLine(to: CGPoint(x: x, y: size.height))
          context.stroke(line, with: .color(.green.opacity(gridOpacity)), lineWidth: 0.5)
        }
        
        for x in stride(from: centerX - gridSpacing, through: 0, by: -gridSpacing) {
          var line = Path()
          line.move(to: CGPoint(x: x, y: 0))
          line.addLine(to: CGPoint(x: x, y: size.height))
          context.stroke(line, with: .color(.green.opacity(gridOpacity)), lineWidth: 0.5)
        }
        
        for y in stride(from: centerY, through: size.height, by: gridSpacing) {
          var line = Path()
          line.move(to: CGPoint(x: 0, y: y))
          line.addLine(to: CGPoint(x: size.width, y: y))
          context.stroke(line, with: .color(.green.opacity(gridOpacity)), lineWidth: 0.5)
        }
        
        for y in stride(from: centerY - gridSpacing, through: 0, by: -gridSpacing) {
          var line = Path()
          line.move(to: CGPoint(x: 0, y: y))
          line.addLine(to: CGPoint(x: size.width, y: y))
          context.stroke(line, with: .color(.green.opacity(gridOpacity)), lineWidth: 0.5)
        }

        var hCenter = Path()
        hCenter.move(to: CGPoint(x: 0, y: centerY))
        hCenter.addLine(to: CGPoint(x: size.width, y: centerY))
        context.stroke(hCenter, with: .color(.green.opacity(Constants.centerLineOpacity)), lineWidth: 1.0)

        var vCenter = Path()
        vCenter.move(to: CGPoint(x: centerX, y: 0))
        vCenter.addLine(to: CGPoint(x: centerX, y: size.height))
        context.stroke(vCenter, with: .color(.green.opacity(Constants.centerLineOpacity)), lineWidth: 1.0)

        let audioEnergy = Double(audio.bass + audio.mid + audio.high) / 3.0
        let brightness = min(0.7 + audioEnergy * 0.3, 1.0)

        let trailPath = buildWaveformPath(from: phosphorTrail, size: size)
        let trailGlow: [(width: CGFloat, opacity: Double)] = [
          (16.0, 0.025),
          (10.0, 0.05),
          (6.0, 0.1),
          (3.0, 0.2),
          (1.5, 0.4)
        ]
        for layer in trailGlow {
          context.stroke(
            trailPath,
            with: .color(Color(hue: 0.33,
                              saturation: 0.5,
                              brightness: brightness * 0.6,
                              opacity: layer.opacity)),
            lineWidth: layer.width
          )
        }

        let waveformPath = buildWaveformPath(from: smoothedWaveform, size: size)

        let glowLayers: [(width: CGFloat, opacity: Double)] = [
          (12.0, 0.03),
          (8.0, 0.06),
          (5.0, 0.1),
          (3.0, 0.2),
          (1.5, 0.9)
        ]

        for layer in glowLayers {
          context.stroke(
            waveformPath,
            with: .color(Color(hue: 0.33,
                              saturation: 0.8,
                              brightness: brightness,
                              opacity: layer.opacity)),
            lineWidth: layer.width
          )
        }
      }
      .visualEffect { [curvature = Constants.crtCurvature,
                       scanline = Constants.crtScanlineIntensity,
                       vignette = Constants.crtVignetteStrength] content, proxy in
        content
          .layerEffect(
            ShaderLibrary.crtEffect(
              .float2(proxy.size),
              .float(curvature),
              .float(scanline),
              .float(vignette)
            ),
            maxSampleOffset: CGSize(width: 10, height: 10)
          )
      }
      .onChange(of: timeline.date) { oldValue, newValue in
        let dt = min(Float(newValue.timeIntervalSince(oldValue)), 1.0 / 30.0)
        audio.update(from: audioLevels, dt: dt)

        var rawPeak: Float = 0
        for i in 0..<1024 {
          let v = abs(waveform[i])
          if v > rawPeak { rawPeak = v }
        }

        let retention = Constants.phosphorRetention
        let n = Constants.displayPointCount
        for i in 0..<n {
          phosphorTrail[i] = phosphorTrail[i] * retention + smoothedWaveform[i] * (1.0 - retention)
        }

        if rawPeak < Constants.silenceThreshold {
          for i in 0..<n {
            smoothedWaveform[i] *= Constants.decayFactor
            if abs(smoothedWaveform[i]) < Constants.decayThreshold {
              smoothedWaveform[i] = 0
            }
            phosphorTrail[i] *= Constants.decayFactor
            if abs(phosphorTrail[i]) < Constants.decayThreshold {
              phosphorTrail[i] = 0
            }
          }
        } else {
          downsampleWaveform(into: &downsampleBuffer)
          for i in 0..<n {
            let target = downsampleBuffer[i]
            let current = smoothedWaveform[i]
            let smooth = abs(target) > abs(current) ? Constants.attackSmoothing : Constants.releaseSmoothing
            smoothedWaveform[i] = current * smooth + target * (1.0 - smooth)
          }
        }
      }
      .ignoresSafeArea()
      .accessibilityHidden(true)
    }
  }
}
