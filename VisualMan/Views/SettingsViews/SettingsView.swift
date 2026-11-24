//
//  SettingsView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import SwiftUI
import Dependencies

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Dependency(HapticsManager.self) private var hapticsManager

  var body: some View {
    @Bindable var hapticsManager = hapticsManager

    Form {
      Section {
        Toggle("Bass Haptics", systemImage: "iphone.radiowaves.left.and.right", isOn: $hapticsManager.isEnabled)
          .disabled(!hapticsManager.isSupported)
      } footer: {
        if hapticsManager.isSupported {
          Text("Vibrates along with the bass of the song that is playing.")
        } else {
          Text("This device doesn't support haptics.")
        }
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

#Preview {
  NavigationStack {
    SettingsView()
  }
}
