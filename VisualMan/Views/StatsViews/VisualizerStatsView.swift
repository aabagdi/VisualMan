//
//  VisualizerStatsView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

import SwiftUI
import Dependencies
import Sharing

struct VisualizerStatsView: View {
  @State private var isConfirmingReset = false

  @Dependency(VisualizerUsageManager.self) private var usageManager

  var body: some View {
    let rankings = usageManager.rankings
    let mostUsed = rankings.first(where: \.isUsed)

    List {
      if let mostUsed {
        Section {
          VStack(alignment: .leading, spacing: 4) {
            Text(mostUsed.visualizer.displayName)
              .font(.title2)
              .fontWeight(.bold)
            Text("\(mostUsed.timeOnScreen.onScreenText) on screen")
              .foregroundStyle(.secondary)
            Text(mostUsed.timesSelected.selectionText)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
          .accessibilityElement(children: .combine)
        } header: {
          Text("Most Used")
        }

        Section {
          ForEach(rankings) { ranking in
            UsageRow(ranking: ranking, longestTimeOnScreen: mostUsed.timeOnScreen)
          }
        } header: {
          Text("All Visualizers")
        } footer: {
          Text("""
            Time on screen is counted while a song is playing on this device's screen. \
            Selections are counted each time you pick a different visualizer.
            """)
        }
      }
    }
    .listStyle(.insetGrouped)
    .overlay {
      if mostUsed == nil {
        ContentUnavailableView(
          "No Stats Yet",
          systemImage: "chart.bar",
          description: Text("Open the player and pick a visualizer, and your most used one will show up here.")
        )
      }
    }
    .navigationTitle("Stats")
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Reset", role: .destructive) {
          isConfirmingReset = true
        }
        .disabled(mostUsed == nil)
        .confirmationDialog("Reset visualizer stats?", isPresented: $isConfirmingReset) {
          Button("Reset Stats", role: .destructive) {
            usageManager.reset()
          }
        }
      }
    }
  }
}

private struct UsageRow: View {
  let ranking: VisualizerUsageRanking
  let longestTimeOnScreen: Duration

  private var fraction: Double {
    guard longestTimeOnScreen > .zero else { return 0 }
    return ranking.timeOnScreen / longestTimeOnScreen
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(ranking.visualizer.displayName)
        Spacer()
        Group {
          if ranking.isUsed {
            Text(ranking.timeOnScreen.onScreenText)
          } else {
            Text("Not used yet")
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .monospacedDigit()
      }

      ProgressView(value: fraction)
        .accessibilityHidden(true)

      if ranking.isUsed {
        Text(ranking.timesSelected.selectionText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

private extension Duration {
  var onScreenText: String {
    formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
  }
}

private extension Int {
  var selectionText: LocalizedStringResource {
    "Selected ^[\(self) time](inflect: true)"
  }
}

#Preview(
  traits: .dependencies { _ in
    @Shared(.visualizerUsage) var usage
    $usage.withLock {
      $0.secondsOnScreen = [
        VMVisualizer.navierStokes.usageKey: 5_400,
        VMVisualizer.liquidLight.usageKey: 2_130,
        VMVisualizer.bars.usageKey: 640,
      ]
      $0.timesSelected = [
        VMVisualizer.navierStokes.usageKey: 12,
        VMVisualizer.liquidLight.usageKey: 7,
        VMVisualizer.julia.usageKey: 1,
      ]
    }
  }
) {
  NavigationStack {
    VisualizerStatsView()
  }
}
