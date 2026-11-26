//
//  PaintSurfaceCredits.swift
//  VisualMan
//
//  Created on 11/25/26.
//

import SwiftUI

struct PaintSurfaceCredits: View {
  var body: some View {
    CreditRow(
      title: "Surface Levelling in Viscous Liquids",
      role: "Wet paint levelling",
      attribution: "Orchard, 1963",
      license: nil,
      url: URL(string: "https://doi.org/10.1007/BF03184629"),
      note: """
        Orchard, S.E. On surface levelling in viscous liquids and \
        gels. Appl. sci. Res. 11, 451–464 (1963).
        """
    )

    CreditRow(
      title: "Thin-Layer Theory for Bingham Plastics",
      role: "Paint yield threshold",
      attribution: "Balmforth & Craster, 1999",
      license: nil,
      url: URL(string: "https://doi.org/10.1016/S0377-0257(98)00133-5"),
      note: """
        N.J. Balmforth and R.V. Craster. A consistent thin-layer \
        theory for Bingham plastics. Journal of Non-Newtonian Fluid \
        Mechanics, Volume 84, Issue 1, 1999, Pages 65–81.
        """
    )

    CreditRow(
      title: "IMPaSTo",
      role: "Canvas weave tooth",
      attribution: "Baxter, Wendt & Lin, 2004",
      license: nil,
      url: URL(string: "https://doi.org/10.1145/987657.987665"),
      note: """
        William Baxter, Jeremy Wendt, and Ming C. Lin. 2004. IMPaSTo: \
        a realistic, interactive model for paint. In Proceedings of \
        the 3rd international symposium on Non-photorealistic \
        animation and rendering (NPAR '04). Association for Computing \
        Machinery, New York, NY, USA, 45–148.
        """
    )

    CreditRow(
      title: "Real-Time Oil Painting on Mobile Hardware",
      role: "Paint sag under gravity",
      attribution: "Stuyck, Da, Hadap & Dutré, 2017",
      license: nil,
      url: URL(string: "https://doi.org/10.1111/cgf.12995"),
      note: """
        Stuyck, T., Da, F., Hadap, S. and Dutré, P. (2017), Real-Time \
        Oil Painting on Mobile Hardware. Computer Graphics Forum, 36: \
        69–79.
        """
    )

    CreditRow(
      title: "Wetbrush",
      role: "Bristle stroke texture",
      attribution: "Chen, Kim, Ito & Wang, 2015",
      license: nil,
      url: URL(string: "https://doi.org/10.1145/2816795.2818066"),
      note: """
        Zhili Chen, Byungmoon Kim, Daichi Ito, and Huamin Wang. 2015. \
        Wetbrush: GPU-based 3D painting simulation at the bristle \
        level. ACM Trans. Graph. 34, 6, Article 200 (November 2015), \
        11 pages.
        """
    )

    CreditRow(
      title: "Gloss, Color, and Topography Scanning",
      role: "Gloss as a separate surface map",
      attribution: "Elkhuizen et al., 2019",
      license: nil,
      url: URL(string: "https://doi.org/10.1145/3317949"),
      note: """
        Willemijn Elkhuizen, Tessa Essers, Yu Song, Jo Geraedts, \
        Clemens Weijkamp, Joris Dik, and Sylvia Pont. 2019. Gloss, \
        Color, and Topography Scanning for Reproducing a Painting’s \
        Appearance Using 3D Printing. J. Comput. Cult. Herit. 12, 4, \
        Article 27 (December 2019), 22 pages.
        """
    )

    CreditRow(
      title: "Paint Cracking and Peeling",
      role: "Stress-driven cracks",
      attribution: "Paquette, Poulin & Drettakis, 2002",
      license: nil,
      url: URL(string: "https://doi.org/10.20380/GI2002.08"),
      note: """
        Eric Paquette, Pierre Poulin, and George Drettakis. 2002. The \
        Simulation of Paint Cracking and Peeling. In Proceedings of \
        Graphics Interface 2002, Calgary, Alberta, Canada, 27–29 May \
        2002, 59–68.
        """
    )

    CreditRow(
      title: "Generating Surface Crack Patterns",
      role: "Stress-driven cracks",
      attribution: "Iben & O'Brien, 2006",
      license: nil,
      url: URL(string: "https://doi.org/10.2312/SCA/SCA06/177-185"),
      note: """
        Hayley N. Iben and James F. O'Brien. 2006. Generating Surface \
        Crack Patterns. In ACM SIGGRAPH / Eurographics Symposium on \
        Computer Animation, Marie-Paule Cani and James O'Brien \
        (Eds.). The Eurographics Association, 177–185.
        """
    )

    CreditRow(
      title: "LEAN Mapping",
      role: "Highlight antialiasing",
      attribution: "Olano & Baker, 2010",
      license: nil,
      url: URL(string: "https://doi.org/10.1145/1730804.1730834"),
      note: """
        Marc Olano and Dan Baker. 2010. LEAN mapping. In Proceedings \
        of the 2010 ACM SIGGRAPH symposium on Interactive 3D Graphics \
        and Games (I3D '10). Association for Computing Machinery, \
        New York, NY, USA, 181–188.
        """
    )

    CreditRow(
      title: "Filtering Distributions of Normals",
      role: "Highlight antialiasing",
      attribution: "Kaplanyan, Hill, Patney & Lefohn, 2016",
      license: nil,
      url: URL(string: "https://doi.org/10.2312/hpg.20161201"),
      note: """
        Anton S. Kaplanyan, Stephen Hill, Anjul Patney, and Aaron \
        Lefohn. 2016. Filtering Distributions of Normals for Shading \
        Antialiasing. In Eurographics/ ACM SIGGRAPH Symposium on High \
        Performance Graphics, Ulf Assarsson and Warren Hunt (Eds.). \
        The Eurographics Association, 151–162.
        """
    )
  }
}
