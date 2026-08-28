import SwiftUI

/// The carafe silhouette — the app's visual identity, and the single source of
/// truth for both the menu bar icon and the popup gauge.
///
/// The profile is authored in a normalised unit square (0…1, origin top-left) and
/// then fitted into whatever rect it is handed, preserving `aspectRatio` and
/// centring the result. That means the same shape reads correctly at 18pt in the
/// menu bar and at 200pt in the popup without a separate icon asset that could
/// drift out of sync.
///
/// The outline is symmetric by construction: every horizontal coordinate is
/// expressed through `Profile`, and the left edge mirrors the right.
struct CarafeShape: Shape, InsettableShape {
    /// Width ÷ height of the silhouette's bounding box.
    static let aspectRatio: CGFloat = 0.72

    var insetAmount: CGFloat = 0

    // MARK: - Profile

    /// Named coordinates of the silhouette, in the unit square.
    ///
    /// Three details separate a carafe from the laboratory flask this shape can
    /// easily drift into:
    ///
    /// 1. **A rounded shoulder.** The flare begins gradually just below the neck
    ///    rather than leaving it as a straight diagonal. A cone reads as a flask.
    /// 2. **A short, fairly wide neck.** A long narrow neck also reads as a flask
    ///    (or a bottle).
    /// 3. **A belly that tucks back in.** The body is widest around 70% of the
    ///    height and draws in slightly toward the foot, which is what gives a
    ///    carafe its poise. A shape widest at the very bottom looks like a beaker.
    ///
    /// Every segment is monotonic in Y, which lets `unitRightEdge(atUnitY:)`
    /// recover X by binary search.
    private enum Profile {
        /// The rim: a narrow opening, slightly wider than the neck below it, which
        /// reads as a pouring lip without needing a separate curve.
        static let rimY: CGFloat = 0.020
        static let rimRight: CGFloat = 0.621

        /// The narrowest point, at the base of a deliberately short neck.
        static let neckY: CGFloat = 0.142
        static let neckRight: CGFloat = 0.598

        /// The widest point of the belly.
        static let bellyY: CGFloat = 0.700
        static let bellyRight: CGFloat = 0.942

        /// Control points for the shoulder-and-belly curve.
        ///
        /// `shoulderControl` sits close to the neck in X but well below it in Y, so
        /// the curve eases away from the neck instead of snapping into a diagonal —
        /// this is what produces the rounded shoulder.
        /// `bellyControl` shares its X with the belly so the curve arrives vertically
        /// at the widest point.
        static let shoulderControl = CGPoint(x: 0.628, y: 0.286)
        static let bellyControl = CGPoint(x: 0.942, y: 0.474)

        /// Where the belly has drawn back in, just above the foot.
        static let baseY: CGFloat = 0.946
        static let baseRight: CGFloat = 0.898
        /// Keeps the tuck vertical as it leaves the belly.
        static let tuckControl = CGPoint(x: 0.942, y: 0.862)

        /// The rounded foot.
        static let bottomY: CGFloat = 0.990
        static let bottomRight: CGFloat = 0.822

        static func mirrored(_ x: CGFloat) -> CGFloat { 1 - x }
    }

    // MARK: - Shape

    func path(in rect: CGRect) -> Path {
        let box = Self.fittedBox(in: rect.insetBy(dx: insetAmount, dy: insetAmount))

        // Map a unit-square coordinate into the fitted box.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
        }
        func point(_ p: CGPoint) -> CGPoint { point(p.x, p.y) }
        func mirrored(_ x: CGFloat, _ y: CGFloat) -> CGPoint { point(Profile.mirrored(x), y) }
        func mirrored(_ p: CGPoint) -> CGPoint { point(Profile.mirrored(p.x), p.y) }

        var path = Path()

        // Rim, left to right.
        path.move(to: mirrored(Profile.rimRight, Profile.rimY))
        path.addLine(to: point(Profile.rimRight, Profile.rimY))

        // Right side, descending: neck → shoulder → belly → tuck → foot.
        path.addLine(to: point(Profile.neckRight, Profile.neckY))
        path.addCurve(
            to: point(Profile.bellyRight, Profile.bellyY),
            control1: point(Profile.shoulderControl),
            control2: point(Profile.bellyControl)
        )
        path.addQuadCurve(
            to: point(Profile.baseRight, Profile.baseY),
            control: point(Profile.tuckControl)
        )
        path.addQuadCurve(
            to: point(Profile.bottomRight, Profile.bottomY),
            control: point(Profile.baseRight, Profile.bottomY)
        )

        // Base, right to left.
        path.addLine(to: mirrored(Profile.bottomRight, Profile.bottomY))

        // Left side, ascending — the mirror of the right.
        path.addQuadCurve(
            to: mirrored(Profile.baseRight, Profile.baseY),
            control: mirrored(Profile.baseRight, Profile.bottomY)
        )
        path.addQuadCurve(
            to: mirrored(Profile.bellyRight, Profile.bellyY),
            control: mirrored(Profile.tuckControl)
        )
        path.addCurve(
            to: mirrored(Profile.neckRight, Profile.neckY),
            control1: mirrored(Profile.bellyControl),
            control2: mirrored(Profile.shoulderControl)
        )
        path.closeSubpath()

        return path
    }

    func inset(by amount: CGFloat) -> CarafeShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    // MARK: - Geometry helpers

    /// The largest rect of `aspectRatio` that fits inside `rect`, centred.
    ///
    /// Exposed so the gauge can align graduation ticks to the same box the
    /// silhouette is drawn in.
    static func fittedBox(in rect: CGRect) -> CGRect {
        let height = min(rect.height, rect.width / aspectRatio)
        let width = height * aspectRatio
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// The vertical span the water occupies, as unit-square Y coordinates.
    ///
    /// Water stops below the shoulder — a carafe filled into its neck would look
    /// wrong, and it keeps the graduations on the part of the body wide enough to
    /// label.
    static let waterTopY: CGFloat = 0.285
    static let waterBottomY: CGFloat = Profile.bottomY

    /// Converts a 0…1 fill fraction into a Y coordinate in `rect`.
    ///
    /// A fraction of 1 sits at `waterTopY` (full) and 0 at `waterBottomY` (empty).
    static func waterLevelY(for fraction: CGFloat, in box: CGRect) -> CGFloat {
        let clamped = min(1, max(0, fraction))
        let unitY = waterBottomY - (waterBottomY - waterTopY) * clamped
        return box.minY + unitY * box.height
    }

    /// The X coordinate of the silhouette's right edge at a given unit Y, in unit space.
    ///
    /// Graduation ticks use this to hug the inner wall as it curves, instead of
    /// hanging off a single straight line that would punch through the shoulder.
    /// The left edge is the mirror of this by symmetry.
    static func unitRightEdge(atUnitY y: CGFloat) -> CGFloat {
        let y = min(Profile.bottomY, max(Profile.rimY, y))

        switch y {
        case ..<Profile.neckY:
            return interpolate(y, from: (Profile.rimY, Profile.rimRight), to: (Profile.neckY, Profile.neckRight))

        case ..<Profile.bellyY:
            return cubicX(
                atY: y,
                p0: CGPoint(x: Profile.neckRight, y: Profile.neckY),
                c1: Profile.shoulderControl,
                c2: Profile.bellyControl,
                p3: CGPoint(x: Profile.bellyRight, y: Profile.bellyY)
            )

        case ..<Profile.baseY:
            return quadraticX(
                atY: y,
                p0: CGPoint(x: Profile.bellyRight, y: Profile.bellyY),
                control: Profile.tuckControl,
                p2: CGPoint(x: Profile.baseRight, y: Profile.baseY)
            )

        default:
            return quadraticX(
                atY: y,
                p0: CGPoint(x: Profile.baseRight, y: Profile.baseY),
                control: CGPoint(x: Profile.baseRight, y: Profile.bottomY),
                p2: CGPoint(x: Profile.bottomRight, y: Profile.bottomY)
            )
        }
    }

    private static func interpolate(
        _ y: CGFloat,
        from start: (y: CGFloat, x: CGFloat),
        to end: (y: CGFloat, x: CGFloat)
    ) -> CGFloat {
        guard end.y > start.y else { return start.x }
        let t = (y - start.y) / (end.y - start.y)
        return start.x + (end.x - start.x) * t
    }

    private static func cubicX(atY y: CGFloat, p0: CGPoint, c1: CGPoint, c2: CGPoint, p3: CGPoint) -> CGFloat {
        func value(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
            let mt = 1 - t
            return mt * mt * mt * a + 3 * mt * mt * t * b + 3 * mt * t * t * c + t * t * t * d
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if value(mid, p0.y, c1.y, c2.y, p3.y) < y { low = mid } else { high = mid }
        }
        return value((low + high) / 2, p0.x, c1.x, c2.x, p3.x)
    }

    private static func quadraticX(atY y: CGFloat, p0: CGPoint, control: CGPoint, p2: CGPoint) -> CGFloat {
        func value(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat, _ c: CGFloat) -> CGFloat {
            let mt = 1 - t
            return mt * mt * a + 2 * mt * t * b + t * t * c
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if value(mid, p0.y, control.y, p2.y) < y { low = mid } else { high = mid }
        }
        return value((low + high) / 2, p0.x, control.x, p2.x)
    }
}

// MARK: - Previews

#Preview("Carafe outline") {
    VStack(spacing: 24) {
        CarafeShape()
            .strokeBorder(.primary.opacity(0.55), lineWidth: 2)
            .frame(width: 160, height: 222)

        HStack(alignment: .bottom, spacing: 20) {
            ForEach([16.0, 18.0, 22.0, 64.0], id: \.self) { size in
                CarafeShape()
                    .strokeBorder(.primary, lineWidth: size < 24 ? 1 : 1.5)
                    .frame(width: size * CarafeShape.aspectRatio, height: size)
            }
        }
    }
    .padding(40)
}
