//
//  CreditsView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import SwiftUI

struct CreditsView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Acknowledgements")
            .font(.title2)
            .fontWeight(.bold)

          Text("""
            Special thanks to \
            [Point-Free](https://www.pointfree.co) for their \
            [Dependencies](https://github.com/pointfreeco/swift-dependencies) \
            library.
            """)

          Text("""
            Pigment mixing in the Abstract Expressionism visualizer is \
            powered by [Mixbox](https://github.com/scrtwpns/mixbox) by \
            Secret Weapons. Copyright © Secret Weapons. Licensed under \
            [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). \
            Used in modified form (integrated into the rendering pipeline). \
            Provided as-is, without warranty of any kind.
            """)
        }

        Divider()

        VStack(alignment: .leading, spacing: 12) {
          Text("License")
            .font(.title2)
            .fontWeight(.bold)

          Text("""
            VisualMan, except where otherwise noted, is licensed under the \
            MIT License. The Mixbox component is separately licensed under \
            CC BY-NC 4.0; full text of both licenses follows.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("MIT License")
            .font(.headline)

          Text("""
            Copyright © 2025 Aadit Bagdi

            Permission is hereby granted, free of charge, to any person obtaining a copy \
            of this software and associated documentation files (the "Software"), to deal \
            in the Software without restriction, including without limitation the rights \
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
            copies of the Software, and to permit persons to whom the Software is \
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all \
            copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
            SOFTWARE.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("Mixbox — CC BY-NC 4.0")
            .font(.headline)

          Text("""
            Mixbox by Secret Weapons. Copyright © 2022 Secret Weapons. \
            Original project: \
            [github.com/scrtwpns/mixbox](https://github.com/scrtwpns/mixbox)

            Files in this project licensed under CC BY-NC 4.0:
              • Mixbox.metal (Metal shader implementation)
              • mixbox_lut.png (lookup table data)

            This software is licensed under the Creative Commons \
            Attribution-NonCommercial 4.0 International Public License \
            ("CC BY-NC 4.0"). The full license text is available at \
            [creativecommons.org/licenses/by-nc/4.0/legalcode]\
            (https://creativecommons.org/licenses/by-nc/4.0/legalcode).

            Summary of terms (this summary is not a substitute for the \
            license):

            You are free to:
              • Share — copy and redistribute the material in any medium \
                or format
              • Adapt — remix, transform, and build upon the material

            Under the following terms:
              • Attribution — You must give appropriate credit, provide a \
                link to the license, and indicate if changes were made.
              • NonCommercial — You may not use the material for \
                commercial purposes.
              • No additional restrictions — You may not apply legal \
                terms or technological measures that legally restrict \
                others from doing anything the license permits.

            UNLESS OTHERWISE SEPARATELY UNDERTAKEN BY THE LICENSOR, TO THE \
            EXTENT POSSIBLE, THE LICENSOR OFFERS THE LICENSED MATERIAL \
            AS-IS AND AS-AVAILABLE, AND MAKES NO REPRESENTATIONS OR \
            WARRANTIES OF ANY KIND CONCERNING THE LICENSED MATERIAL, \
            WHETHER EXPRESS, IMPLIED, STATUTORY, OR OTHER.

            TO THE EXTENT POSSIBLE, IN NO EVENT WILL THE LICENSOR BE \
            LIABLE TO YOU ON ANY LEGAL THEORY (INCLUDING, WITHOUT \
            LIMITATION, NEGLIGENCE) OR OTHERWISE FOR ANY DIRECT, SPECIAL, \
            INDIRECT, INCIDENTAL, CONSEQUENTIAL, PUNITIVE, EXEMPLARY, OR \
            OTHER LOSSES, COSTS, EXPENSES, OR DAMAGES ARISING OUT OF THIS \
            PUBLIC LICENSE OR USE OF THE LICENSED MATERIAL.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding()
    }
    .navigationTitle("Credits")
    .toolbar(.hidden, for: .tabBar)
  }
}

#Preview {
  NavigationStack {
    CreditsView()
  }
}
