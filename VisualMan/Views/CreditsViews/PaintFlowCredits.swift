//
//  PaintFlowCredits.swift
//  VisualMan
//
//  Created on 11/25/26.
//

import SwiftUI

struct PaintFlowCredits: View {
  var body: some View {
    CreditRow(
      title: "Real-time Viscous Thin Films",
      role: "Runs, drips, and surface tension in wet paint",
      attribution: "Vantzos, Raz & Ben-Chen, 2018",
      license: nil,
      url: URL(string: "https://doi.org/10.1145/3272127.3275086"),
      note: """
        Orestis Vantzos, Saar Raz, and Mirela Ben-Chen. 2018. \
        Real-time Viscous Thin Films. ACM Trans. Graph. 37, 6, \
        Article 281 (November 2018), 10 pages.
        """
    )

    CreditRow(
      title: "Long-Scale Evolution of Thin Liquid Films",
      role: "Thin-film flow equation",
      attribution: "Oron, Davis & Bankoff, 1997",
      license: nil,
      url: URL(string: "https://doi.org/10.1103/RevModPhys.69.931"),
      note: """
        Alexander Oron, Stephen H. Davis, and S. George Bankoff. \
        Long-scale evolution of thin liquid films. Rev. Mod. Phys. \
        69, 931–980 (1997).
        """
    )

    CreditRow(
      title: "Schemes for the Thin Film Equation",
      role: "Flow between neighbouring cells",
      attribution: "Grün & Rumpf, 2000",
      license: nil,
      url: URL(string: "https://doi.org/10.1007/s002110000197"),
      note: """
        Grün, G., Rumpf, M. Nonnegativity preserving convergent \
        schemes for the thin film equation. Numer. Math. 87, \
        113–152 (2000).
        """
    )

    CreditRow(
      title: "Schemes for Lubrication-Type Equations",
      role: "Flow between neighbouring cells",
      attribution: "Zhornitskaya & Bertozzi, 2000",
      license: nil,
      url: URL(string: "https://doi.org/10.1137/S0036142998335698"),
      note: """
        L. Zhornitskaya and A. L. Bertozzi. Positivity-Preserving \
        Numerical Schemes for Lubrication-Type Equations. SIAM J. \
        Numer. Anal., Vol. 37, No. 2, pp. 523–555 (2000).
        """
    )

    CreditRow(
      title: "Viscous Current Down a Slope",
      role: "Paint runs under gravity",
      attribution: "Huppert, 1982",
      license: nil,
      url: URL(string: "https://doi.org/10.1038/300427a0"),
      note: """
        Huppert, H. Flow and instability of a viscous current down a \
        slope. Nature 300, 427–429 (1982).
        """
    )

    CreditRow(
      title: "Viscoplastic Flow over an Inclined Surface",
      role: "Thickness a wet layer holds before it runs",
      attribution: "Balmforth, Craster, Rust & Sassi, 2006",
      license: nil,
      url: URL(string: "https://doi.org/10.1016/j.jnnfm.2006.07.010"),
      note: """
        N.J. Balmforth, R.V. Craster, A.C. Rust, and R. Sassi. \
        Viscoplastic flow over an inclined surface. Journal of \
        Non-Newtonian Fluid Mechanics, Volume 139, Issues 1–2, 2006, \
        Pages 103–127.
        """
    )

    CreditRow(
      title: "Fingering Instabilities of Driven Spreading Films",
      role: "Fingers at drip fronts",
      attribution: "Troian, Herbolzheimer, Safran & Joanny, 1989",
      license: nil,
      url: URL(string: "https://doi.org/10.1209/0295-5075/10/1/005"),
      note: """
        S. M. Troian, E. Herbolzheimer, S. A. Safran, and J. F. \
        Joanny. Fingering Instabilities of Driven Spreading Films. \
        Europhys. Lett., 10 (1), pp. 25–30 (1989).
        """
    )

    CreditRow(
      title: "Instabilities in Gravity Driven Flow",
      role: "Fingers at drip fronts",
      attribution: "Kondic, 2003",
      license: nil,
      url: URL(string: "https://doi.org/10.1137/S003614450240135"),
      note: """
        L. Kondic. Instabilities in Gravity Driven Flow of Thin Fluid \
        Films. SIAM Rev., Vol. 45, No. 1, pp. 95–115 (2003).
        """
    )

    CreditRow(
      title: "Thin Films Flowing Down Inverted Substrates",
      role: "Fingers at drip fronts",
      attribution: "Lin, Kondic & Filippov, 2012",
      license: nil,
      url: URL(string: "https://doi.org/10.1063/1.3682001"),
      note: """
        T.-S. Lin, L. Kondic, and A. Filippov. Thin films flowing \
        down inverted substrates: Three-dimensional flow. Phys. \
        Fluids 24, 022105 (2012).
        """
    )
  }
}
