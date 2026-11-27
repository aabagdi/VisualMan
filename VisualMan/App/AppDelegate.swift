//
//  AppDelegate.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import Intents
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
    intent is INPlayMediaIntent ? PlayMediaIntentHandler() : nil
  }
}
