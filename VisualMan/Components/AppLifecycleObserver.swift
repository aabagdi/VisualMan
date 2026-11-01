//
//  AppLifecycleObserver.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/1/26.
//

import UIKit

/// Calls back when the app enters the background and returns to the
/// foreground. These are the boundaries for GPU submission permission, so the
/// Metal host views use them to pause and resume drawing. Inactive-but-visible
/// states (Control Centre, notifications) still allow GPU work and are ignored.
@MainActor
final class AppLifecycleObserver {
  nonisolated(unsafe) private var tokens: [any NSObjectProtocol] = []

  init(onBackground: @escaping @MainActor () -> Void,
       onForeground: @escaping @MainActor () -> Void) {
    let center = NotificationCenter.default
    tokens = [
      center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                         object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { onBackground() }
      },
      center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                         object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { onForeground() }
      }
    ]
  }

  deinit {
    tokens.forEach { NotificationCenter.default.removeObserver($0) }
  }
}
