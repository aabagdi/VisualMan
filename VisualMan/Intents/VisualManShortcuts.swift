//
//  VisualManShortcuts.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents

nonisolated struct VisualManShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: PlaySongIntent(),
      phrases: [
        "Play \(\.$song) on \(.applicationName)",
        "Play \(\.$song) in \(.applicationName)",
        "Play a song on \(.applicationName) with the \(\.$visualizer) visualizer",
        "Play music on \(.applicationName) with \(\.$visualizer)",
        "Play a song in \(.applicationName)",
      ],
      shortTitle: "Play Song",
      systemImageName: "music.note"
    )
    AppShortcut(
      intent: OpenVisualizerIntent(),
      phrases: [
        "Open \(\.$visualizer) in \(.applicationName)",
        "Show \(\.$visualizer) in \(.applicationName)",
        "Switch \(.applicationName) to \(\.$visualizer)",
        "Switch to \(\.$visualizer) in \(.applicationName)",
        "Change the \(.applicationName) visualizer to \(\.$visualizer)",
        "Open a visualizer in \(.applicationName)",
      ],
      shortTitle: "Open Visualizer",
      systemImageName: "waveform"
    )
    AppShortcut(
      intent: OpenFavoriteVisualizerIntent(),
      phrases: [
        "Open my favorite visualizer in \(.applicationName)",
        "Open my favourite visualizer in \(.applicationName)",
      ],
      shortTitle: "Favorite Visualizer",
      systemImageName: "star.fill"
    )
    AppShortcut(
      intent: PausePlaybackIntent(),
      phrases: [
        "Pause \(.applicationName)",
        "Pause the music in \(.applicationName)",
      ],
      shortTitle: "Pause",
      systemImageName: "pause.fill"
    )
    AppShortcut(
      intent: ResumePlaybackIntent(),
      phrases: [
        "Resume \(.applicationName)",
        "Resume the music in \(.applicationName)",
      ],
      shortTitle: "Resume",
      systemImageName: "play.fill"
    )
    AppShortcut(
      intent: NextSongIntent(),
      phrases: [
        "Next song in \(.applicationName)",
        "Skip this song in \(.applicationName)",
      ],
      shortTitle: "Next Song",
      systemImageName: "forward.fill"
    )
    AppShortcut(
      intent: PreviousSongIntent(),
      phrases: [
        "Previous song in \(.applicationName)",
        "Go back a song in \(.applicationName)",
      ],
      shortTitle: "Previous Song",
      systemImageName: "backward.fill"
    )
    AppShortcut(
      intent: TurnOnSettingIntent(),
      phrases: [
        "Turn on \(\.$setting) in \(.applicationName)",
        "Enable \(\.$setting) in \(.applicationName)",
      ],
      shortTitle: "Turn On Setting",
      systemImageName: "togglepower"
    )
    AppShortcut(
      intent: TurnOffSettingIntent(),
      phrases: [
        "Turn off \(\.$setting) in \(.applicationName)",
        "Disable \(\.$setting) in \(.applicationName)",
      ],
      shortTitle: "Turn Off Setting",
      systemImageName: "poweroff"
    )
    AppShortcut(
      intent: SetIntensityIntent(),
      phrases: [
        "Set the \(.applicationName) intensity to \(\.$intensity)",
        "Make \(.applicationName) \(\.$intensity)",
      ],
      shortTitle: "Set Intensity",
      systemImageName: "waveform.path"
    )
  }
}
