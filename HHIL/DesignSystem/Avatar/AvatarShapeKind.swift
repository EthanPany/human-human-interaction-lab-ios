import Foundation
import CoreGraphics

/// The avatar body. Every shape is a polar radius function r(θ), so any two
/// shapes can morph into each other by blending radii, and all of them can
/// wobble like jelly with the same code.
///
/// Units: radius 1 is the largest circle that fits the drawing box. θ = 0 is
/// to the right, θ grows clockwise (y points down, like the screen).
enum AvatarShapeKind: String, CaseIterable, Identifiable, Codable {
    case blob, puzzle, circle, triangle, square, pill, flower

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blob: return "Blob"
        case .puzzle: return "Puzzle"
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        case .square: return "Square"
        case .pill: return "Pill"
        case .flower: return "Flower"
        }
    }

    init(serverValue: String?) {
        self = serverValue.flatMap(AvatarShapeKind.init(rawValue:)) ?? .blob
    }

    /// Body radius at angle θ. `phase` slowly advances for the living wobble.
    func radius(_ θ: Double, phase: Double) -> Double {
        let base: Double
        switch self {
        case .circle:
            base = 0.9
        case .blob:
            // Bean like, a little flatter at the bottom (the designer's blobs)
            let flat = sin(θ) > 0 ? 1 - 0.1 * pow(sin(θ), 4) : 1
            base = (0.88 + 0.05 * sin(3 * θ + phase) + 0.035 * sin(5 * θ - 0.7 * phase) + 0.03 * cos(2 * θ)) * flat
        case .square:
            base = 0.84 * Self.superellipse(θ, a: 1, b: 1, n: 4.5)
        case .pill:
            base = 0.95 * Self.superellipse(θ, a: 1, b: 0.74, n: 2.6)
        case .triangle:
            // Rounded triangle, point up. Distance to the nearest edge of a
            // regular triangle, softened toward a circle so the corners are round.
            let period = 2 * Double.pi / 3
            let u = θ + Double.pi / 2
            let d = Self.positiveMod(u, period) - period / 2
            let triangle = 0.5 / cos(d) // circumradius 1
            base = 1.12 * (0.8 * triangle + 0.2 * 0.62)
        case .flower:
            base = 0.8 + 0.12 * cos(6 * θ + 0.15 * phase)
        case .puzzle:
            // Rounded square with two knobs (right and top), like the designer's piece
            let square = 0.74 * Self.superellipse(θ, a: 1, b: 1, n: 3.4)
            let right = Self.bump(θ, at: 0, width: 0.24)
            let top = Self.bump(θ, at: -Double.pi / 2, width: 0.24)
            let socket = Self.bump(θ, at: Double.pi, width: 0.2)
            base = square + 0.22 * right + 0.22 * top - 0.1 * socket
        }
        // Living jelly wobble shared by all shapes
        let wobble = 0.018 * sin(2 * θ + phase) + 0.012 * sin(3 * θ - 1.3 * phase)
        return base + wobble
    }

    /// Where the shape's visual center sits relative to the box center (in radius units).
    var centerOffset: CGPoint {
        switch self {
        case .triangle: return CGPoint(x: 0, y: 0.18)
        case .pill: return CGPoint(x: 0, y: 0.05)
        default: return .zero
        }
    }

    /// Eye positions (radius units from the visual center) and base eye size.
    var eyes: (left: CGPoint, right: CGPoint, size: Double) {
        switch self {
        case .blob: return (CGPoint(x: -0.3, y: -0.22), CGPoint(x: 0.26, y: -0.06), 0.2)
        case .puzzle: return (CGPoint(x: -0.24, y: -0.06), CGPoint(x: 0.2, y: 0.06), 0.21)
        case .triangle: return (CGPoint(x: -0.2, y: 0.1), CGPoint(x: 0.2, y: 0.1), 0.17)
        case .pill: return (CGPoint(x: -0.3, y: -0.1), CGPoint(x: 0.3, y: -0.1), 0.18)
        case .flower: return (CGPoint(x: -0.24, y: -0.08), CGPoint(x: 0.24, y: -0.08), 0.18)
        case .circle, .square: return (CGPoint(x: -0.28, y: -0.12), CGPoint(x: 0.28, y: -0.12), 0.2)
        }
    }

    // MARK: Math helpers

    static func superellipse(_ θ: Double, a: Double, b: Double, n: Double) -> Double {
        let c = pow(abs(cos(θ) / a), n)
        let s = pow(abs(sin(θ) / b), n)
        return 1 / pow(c + s, 1 / n)
    }

    /// Gaussian bump around angle `at`, wrapping around the circle.
    static func bump(_ θ: Double, at center: Double, width: Double) -> Double {
        var d = positiveMod(θ - center + Double.pi, 2 * Double.pi) - Double.pi
        d /= width
        return exp(-d * d)
    }

    static func positiveMod(_ x: Double, _ m: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }
}
