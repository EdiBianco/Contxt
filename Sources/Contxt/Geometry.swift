// Ported from the Electron prototype's src/common/math.ts (itself ported from
// Kando's src/common/math.ts, MIT), which in turn ported Kando's wedge/angle
// math. Convention: 0° = up, clockwise, in a y-down (isFlipped) coordinate
// space — matches CSS `transform: translate(sin*r, -cos*r)` exactly.

import CoreGraphics

struct Wedge {
    let start: CGFloat
    let end: CGFloat
}

/// Evenly distributes `count` items around a full circle, starting at 0°.
func computeItemAngles(_ count: Int) -> [CGFloat] {
    guard count > 0 else { return [] }
    return (0..<count).map { CGFloat($0) * 360 / CGFloat(count) }
}

/// Wedge boundaries sit half-way between each item and its neighbours.
func computeItemWedges(_ angles: [CGFloat]) -> [Wedge] {
    let count = angles.count
    guard count > 0 else { return [] }
    return angles.enumerated().map { i, angle in
        let prev = angles[(i - 1 + count) % count]
        let next = angles[(i + 1) % count]

        var start = (angle + prev) / 2
        var end = (angle + next) / 2

        // Handle wrap-around at the 0°/360° seam.
        if i == 0 { start -= 180 }
        if i == count - 1 { end += 180 }

        return Wedge(start: start, end: end)
    }
}

func isAngleBetween(_ angle: CGFloat, _ start: CGFloat, _ end: CGFloat) -> Bool {
    let normalized = ((angle - start).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    let span = ((end - start).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return normalized <= span
}

/// Angle in degrees of `point` relative to `center`, 0° = up, clockwise.
func angleFromCenter(_ point: CGPoint, center: CGPoint) -> CGFloat {
    let dx = point.x - center.x
    let dy = point.y - center.y
    var angle = atan2(dx, -dy) * 180 / .pi
    if angle < 0 { angle += 360 }
    return angle
}

/// Offset from center for an item at `angleDeg`, `radius` px out.
func direction(angleDeg: CGFloat, radius: CGFloat) -> CGPoint {
    let rad = angleDeg * .pi / 180
    return CGPoint(x: sin(rad) * radius, y: -cos(rad) * radius)
}
