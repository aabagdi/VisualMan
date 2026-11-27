//
//  SettingsView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import SwiftUI
import Dependencies
import Intents

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Dependency(HapticsManager.self) private var hapticsManager
  @Dependency(AccessibilityManager.self) private var accessibilityManager

  var body: some View {
    @Bindable var hapticsManager = hapticsManager
    @Bindable var accessibilityManager = accessibilityManager

    Form {
      Section {
        Toggle(
          "Bass Haptics",
          systemImage: "iphone.radiowaves.left.and.right",
          isOn: $hapticsManager.isActive
        )
        .disabled(!hapticsManager.isSupported)

        if hapticsManager.isActive {
          VStack(alignment: .leading) {
            Label("Haptic Strength", systemImage: "dial.medium")
              .accessibilityHidden(true)
            DetentSlider(
              value: $hapticsManager.strength,
              range: HapticsManager.Constants.strengthRange,
              detent: HapticsManager.Constants.defaultStrength,
              snapDistance: HapticsManager.Constants.strengthSnapDistance,
              accessibilityLabel: "Haptic Strength"
            )
          }
        }
      } header: {
        Text("Haptics")
      } footer: {
        if hapticsManager.isSupported {
          Text("Vibrates along with the bass of the song that is playing, so you can feel the beat.")
        } else {
          Text("This device doesn't support haptics.")
        }
      }

      Section {
        Picker("Intensity", systemImage: "waveform", selection: $accessibilityManager.intensity) {
          ForEach(VisualizerIntensity.allCases, id: \.self) { intensity in
            Text(intensity.displayName)
          }
        }

        Toggle("Reduce Flashing", systemImage: "bolt.slash", isOn: $accessibilityManager.reducesFlashing)
      } header: {
        Text("Visualizers")
      } footer: {
        Text("""
          Intensity sets how strongly the visualizers react to the music. Reduce Flashing slows down \
          sudden brightness changes. Both follow Reduce Motion and Dim Flashing Lights in iOS \
          Settings until you change them here. Choosing the same setting as iOS makes it follow iOS again.
          """)
      }

      Section {
        Toggle(
          "Keep Controls Visible",
          systemImage: "rectangle.bottomthird.inset.filled",
          isOn: $accessibilityManager.keepsControlsVisible
        )
      } header: {
        Text("Player")
      } footer: {
        Text("""
          Tapping the visualizer won't hide the playback controls. They always stay visible while \
          VoiceOver or Switch Control is on.
          """)
      }

      SiriAccessSection()

      Section {
        NavigationLink {
          VisualizerStatsView()
        } label: {
          Label("Visualizer Stats", systemImage: "chart.bar")
        }
      } header: {
        Text("Stats")
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done", systemImage: "checkmark") {
          dismiss()
        }
      }
    }
  }
}

private struct SiriAccessSection: View {
  @State private var status = INPreferences.siriAuthorizationStatus()
  @Environment(\.openURL) private var openURL

  private nonisolated static func requestSiriAuthorization() async -> INSiriAuthorizationStatus {
    await withCheckedContinuation { continuation in
      INPreferences.requestSiriAuthorization { continuation.resume(returning: $0) }
    }
  }

  var body: some View {
    Section {
      switch status {
      case .authorized:
        Label("Siri Can Play Music", systemImage: "checkmark.circle")
      case .denied, .restricted:
        Button("Open Settings", systemImage: "gear") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        }
      default:
        Button("Allow Siri to Play Music", systemImage: "music.mic") {
          Task { status = await Self.requestSiriAuthorization() }
        }
      }
    } header: {
      Text("Siri")
    } footer: {
      switch status {
      case .denied, .restricted:
        Text("Siri isn't allowed to use VisualMan. You can turn it on in Settings.")
      default:
        Text("""
          Lets you ask Siri to play songs from your library, like “Play Come As You Are on VisualMan.” \
          Needed when Apple Intelligence is off or not available.
          """)
      }
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView()
  }
}
