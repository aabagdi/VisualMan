//
//  LibraryLoadingView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct LibraryLoadingView: View {
  var body: some View {
    ProgressView {
      VStack {
        Text("Library loading!")
          .font(.headline)
      }
    }
  }
}

#Preview {
  LibraryLoadingView()
}
