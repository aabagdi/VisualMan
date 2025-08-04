//
//  MusicPlayerTabView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/3/25.
//

import Foundation
import SwiftUI

struct MusicPlayerTabView: View {
  @Environment(\.tabViewBottomAccessoryPlacement) private var placement
  
  let sources: [any AudioSource]
  
  var body: some View {
    switch placement {
    case .inline:
      MusicTabInlineView()
    case .expanded:
      MusicTabExpandedView()
    default:
      Text("Woo")
    }
  }
}
