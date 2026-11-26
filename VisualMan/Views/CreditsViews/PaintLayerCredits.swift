//
//  PaintLayerCredits.swift
//  VisualMan
//
//  Created on 11/25/26.
//

import SwiftUI

struct PaintLayerCredits: View {
  var body: some View {
    CreditRow(
      title: "Computer-Generated Watercolor",
      role: "Glazes and darker wash edges",
      attribution: "Curtis, Anderson, Seims, Fleischer & Salesin, 1997",
      license: nil,
      url: URL(string: "https://doi.org/10.1145/258734.258896"),
      note: """
        Cassidy J. Curtis, Sean E. Anderson, Joshua E. Seims, Kurt W. \
        Fleischer, and David H. Salesin. 1997. Computer-generated \
        watercolor. In Proceedings of the 24th annual conference on \
        Computer graphics and interactive techniques (SIGGRAPH '97). \
        ACM Press, 421–430.
        """
    )

    CreditRow(
      title: "MoXi",
      role: "Washes wicking into the canvas",
      attribution: "Chu & Tai, 2005",
      license: nil,
      url: URL(string: "https://doi.org/10.1145/1073204.1073221"),
      note: """
        Nelson S.-H. Chu and Chiew-Lan Tai. 2005. MoXi: real-time ink \
        dispersion in absorbent paper. ACM Trans. Graph. 24, 3 (July \
        2005), 504–511.
        """
    )

    CreditRow(
      title: "Painting with Drops, Jets, and Sheets",
      role: "Poured paint lines, coils, and drops",
      attribution: "Herczyński, Cernuschi & Mahadevan, 2011",
      license: nil,
      url: URL(string: "https://doi.org/10.1063/1.3603916"),
      note: """
        Andrzej Herczyński, Claude Cernuschi, and L. Mahadevan. 2011. \
        Painting with drops, jets, and sheets. Physics Today 64(6): \
        31–36.
        """
    )

    CreditRow(
      title: "Pollock Avoided Hydrodynamic Instabilities",
      role: "Poured paint lines, coils, and drops",
      attribution: "Palacios, Rosario, Wilhelmus, Zetina & Zenit, 2019",
      license: nil,
      url: URL(string: "https://doi.org/10.1371/journal.pone.0223706"),
      note: """
        Palacios B, Rosario A, Wilhelmus MM, Zetina S, Zenit R (2019) \
        Pollock avoided hydrodynamic instabilities to paint with his \
        dripping technique. PLoS ONE 14(10): e0223706.
        """
    )

    CreditRow(
      title: "Arbitrarily Layered Micro-Facet Surfaces",
      role: "Clear coat over paint",
      attribution: "Weidlich & Wilkie, 2007",
      license: nil,
      url: URL(string: "https://doi.org/10.1145/1321261.1321292"),
      note: """
        Andrea Weidlich and Alexander Wilkie. 2007. Arbitrarily \
        layered micro-facet surfaces. In Proceedings of the 5th \
        international conference on Computer graphics and interactive \
        techniques in Australia and Southeast Asia (GRAPHITE '07). \
        Association for Computing Machinery, New York, NY, USA, \
        171–178.
        """
    )

    CreditRow(
      title: "Microfacet Models for Refraction",
      role: "Highlight shape",
      attribution: "Walter, Marschner, Li & Torrance, 2007",
      license: nil,
      url: URL(string: "https://doi.org/10.2312/EGWR/EGSR07/195-206"),
      note: """
        Bruce Walter, Stephen R. Marschner, Hongsong Li, and Kenneth \
        E. Torrance. 2007. Microfacet Models for Refraction through \
        Rough Surfaces. In Eurographics Symposium on Rendering, Jan \
        Kautz and Sumanta Pattanaik (Eds.). The Eurographics \
        Association, 195–206.
        """
    )
  }
}
