//
//  View+HingeToolbarModifier.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 10/30/26.
//

import Foundation
import SwiftUI

extension TabView {
  @ViewBuilder
  func hingeToolbarOrientation() -> some View {
    if #available(iOS 27.1, *) {
      modifier(HingeToolbarModifier())
    } else {
      self
    }
  }
}

@available(iOS 27.1, *)
struct HingeToolbarModifier: ViewModifier {
  @State var hinge: DeviceHinge?
  
  func body(content: Content) -> some View {
    content
      .defaultTabBarPlacement(hinge?.status == .closed ? .tabBar : .sidebar)
      .toolbarVerticalBehavior(hinge?.status == .closed ? .disabled : .automatic)
      .onHingeChange { _, newContext in
        hinge = newContext.hinge
      }
  }
}
