//
//  CreditsView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import SwiftUI

struct CreditsView: View {
  var body: some View {
    List {
      Section("Abstract Expressionism") {
        CreditRow(
          title: "Mixbox",
          role: "Pigment mixing",
          attribution: "© 2022 Secret Weapons",
          license: "CC BY-NC 4.0",
          url: URL(string: "https://github.com/scrtwpns/mixbox"),
          note: """
            By Šárka Sochorová and Ondřej Jamriška. The Mixbox shader and \
            its lookup table are integrated into the rendering pipeline. \
            Provided as-is, \
            without warranty of any kind.
            """
        )
      }

      Section("Navier-Stokes") {
        CreditRow(
          title: "Covector Fluids",
          role: "Fluid solver method",
          attribution: "Nabizadeh, Wang, Ramamoorthi & Chern, 2022",
          license: nil,
          url: URL(string: "https://doi.org/10.1145/3528223.3530120"),
          note: """
            Mohammad Sina Nabizadeh, Stephanie Wang, Ravi Ramamoorthi, and \
            Albert Chern. 2022. Covector fluids. ACM Transactions on \
            Graphics (TOG), 41, 4, 113:1–113:15.
            """
        )

        CreditRow(
          title: "Stochastic Film Grain",
          role: "Film grain model",
          attribution: "Newson, Delon & Galerne, 2017",
          license: nil,
          url: URL(string: "https://hal.science/hal-01520260"),
          note: """
            A Newson, Julie Delon, B Galerne. A Stochastic Film Grain \
            Model for Resolution-Independent Rendering. Computer \
            Graphics Forum, 2017. ⟨hal-01520260⟩
            """
        )

        CreditRow(
          title: "spectral_film_lut",
          role: "Technicolor No. IV dye spectra, digitized by Jan Lohse",
          attribution: "© 2026 Jan Lohse",
          license: "MIT",
          url: URL(string: "https://github.com/JanLohse/spectral_film_lut"),
          note: nil
        )

        CreditRow(
          title: "Timeline of Historical Film Colors",
          role: "Technicolor No. IV dye measurements",
          attribution: "Barbara Flückiger",
          license: "CC BY-NC-ND 4.0",
          url: URL(string: "https://filmcolors.org/"),
          note: """
            Flueckiger, Barbara (2012 ff.): Timeline of Historical Film \
            Colors. (https://filmcolors.org/).

            Used with the written permission of Prof. Dr. Barbara \
            Flückiger for this non-commercial project. Resampled and \
            normalized for the rendering pipeline.
            """
        )
      }

      Section("Libraries") {
        CreditRow(
          title: "Dependencies",
          role: "Dependency management library",
          attribution: "Special thanks to Point-Free",
          license: nil,
          url: URL(string: "https://github.com/pointfreeco/swift-dependencies"),
          note: nil
        )

        CreditRow(
          title: "Sharing",
          role: "Persistent settings library",
          attribution: "Special thanks to Point-Free",
          license: nil,
          url: URL(string: "https://github.com/pointfreeco/swift-sharing"),
          note: nil
        )
      }

      Section {
        LicenseLink(title: "VisualMan", license: "MIT License", text: LicenseText.visualMan)
        LicenseLink(title: "spectral_film_lut", license: "MIT License", text: LicenseText.spectralFilmLUT)
        LicenseLink(title: "Dependencies", license: "MIT License", text: LicenseText.dependencies)
        LicenseLink(title: "Sharing", license: "MIT License", text: LicenseText.sharing)
        LicenseLink(
          title: "Supporting Libraries",
          license: "MIT, Apache 2.0",
          text: LicenseText.supportingLibraries
        )
        LicenseLink(title: "Mixbox", license: "CC BY-NC 4.0", text: LicenseText.mixbox)
        LicenseLink(
          title: "Timeline of Historical Film Colors",
          license: "CC BY-NC-ND 4.0",
          text: LicenseText.filmColors
        )
      } header: {
        Text("Licenses")
      } footer: {
        Text("""
          VisualMan, except where otherwise noted, is licensed under the \
          MIT License. The Mixbox component is separately licensed under \
          CC BY-NC 4.0. The Technicolor dye spectra come from \
          spectral_film_lut (MIT) and the Timeline of Historical Film \
          Colors (CC BY-NC-ND 4.0), used with the written permission \
          of Prof. Dr. Barbara Flückiger for this non-commercial \
          project. The Dependencies and Sharing libraries by Point-Free, \
          and the Point-Free libraries they build on, are used under the \
          MIT License; Swift Collections is used under the Apache License \
          2.0 with the Runtime Library Exception.
          """)
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Credits")
    .toolbar(.hidden, for: .tabBar)
  }
}

private struct CreditRow: View {
  let title: String
  let role: LocalizedStringResource
  let attribution: LocalizedStringResource
  let license: String?
  let url: URL?
  let note: LocalizedStringResource?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.headline)

        Spacer()

        if let url {
          Link(destination: url) {
            Image(systemName: "arrow.up.right.square")
              .imageScale(.medium)
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Open \(title) website")
        }
      }

      Text(role)
        .font(.subheadline)

      HStack(spacing: 6) {
        Text(attribution)
        if let license {
          Text(license)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      if let note {
        Text(note)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.top, 2)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct LicenseLink: View {
  let title: String
  let license: String
  let text: LocalizedStringKey

  var body: some View {
    NavigationLink {
      ScrollView {
        Text(text)
          .font(.footnote)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.hidden, for: .tabBar)
    } label: {
      LabeledContent(title, value: license)
    }
  }
}

private enum LicenseText {
  static let visualMan: LocalizedStringKey = """
    Copyright © 2025 Aadit Bagdi

    \(mitBody)
    """

  static let spectralFilmLUT: LocalizedStringKey = """
    Copyright © 2026 Jan Lohse

    \(mitBody)
    """

  static let dependencies: LocalizedStringKey = """
    Copyright © 2022 Point-Free, Inc.

    \(mitBody)
    """

  static let sharing: LocalizedStringKey = """
    Copyright © 2024 Point-Free, Inc.

    \(mitBody)
    """

  static let supportingLibraries: LocalizedStringKey = """
    VisualMan also includes these libraries, which Dependencies and \
    Sharing are built on.

    Point-Free libraries (MIT License):
      • Combine Schedulers — Copyright © 2020 Point-Free, Inc.
      • Custom Dump — Copyright © 2021 Point-Free, Inc.
      • Identified Collections — Copyright © 2021 Point-Free, Inc.
      • Issue Reporting (formerly XCTest Dynamic Overlay) — \
    Copyright © 2021 Point-Free, Inc.
      • Clocks — Copyright © 2022 Point-Free
      • Concurrency Extras — Copyright © 2023 Point-Free
      • Perception — Copyright © 2023 Point-Free

    \(mitBody)

    Swift Collections — Copyright © 2021–2026 Apple Inc. and the Swift \
    project authors. Licensed under the Apache License 2.0 with the \
    Runtime Library Exception. The full license text is available at \
    [github.com/apple/swift-collections](https://github.com/apple/swift-collections/blob/main/LICENSE.txt).
    """

  private static let mitBody = """
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
    """

  static let mixbox: LocalizedStringKey = """
    Mixbox by Šárka Sochorová and Ondřej Jamriška (Secret Weapons). \
    Copyright © 2022 Secret Weapons. Original project: \
    [github.com/scrtwpns/mixbox](https://github.com/scrtwpns/mixbox)

    The Mixbox shader and its lookup table are used in this app \
    under CC BY-NC 4.0.

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

    \(ccDisclaimer)
    """

  static let filmColors: LocalizedStringKey = """
    Timeline of Historical Film Colors by Barbara Flückiger. \
    [filmcolors.org](https://filmcolors.org/)

    Data used in this project:
      • Technicolor No. IV dye spectral densities (Samson and \
    Delilah, C. B. DeMille), resampled to 400–720 nm and \
    normalized. No images or text from the Timeline are included.

    Used, including the resampled and normalized data, with the \
    written permission of Prof. Dr. Barbara Flückiger for this \
    non-commercial project.

    This material is licensed under the Creative Commons \
    Attribution-NonCommercial-NoDerivatives 4.0 International \
    Public License ("CC BY-NC-ND 4.0"). The full license text is \
    available at \
    [creativecommons.org/licenses/by-nc-nd/4.0/legalcode]\
    (https://creativecommons.org/licenses/by-nc-nd/4.0/legalcode).

    Summary of terms (this summary is not a substitute for the \
    license):

    You are free to:
      • Share — copy and redistribute the material in any medium \
    or format

    Under the following terms:
      • Attribution — You must give appropriate credit, provide a \
    link to the license, and indicate if changes were made.
      • NonCommercial — You may not use the material for \
    commercial purposes.
      • NoDerivatives — If you remix, transform, or build upon the \
    material, you may not distribute the modified material.
      • No additional restrictions — You may not apply legal \
    terms or technological measures that legally restrict \
    others from doing anything the license permits.

    \(ccDisclaimer)
    """

  private static let ccDisclaimer = """
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
    """
}

#Preview {
  NavigationStack {
    CreditsView()
  }
}
