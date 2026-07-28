import AppKit
import SwiftUI

struct XLogo: View {
    var size: CGFloat = 12

    var body: some View {
        XLogoShape()
            .fill(.primary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct XLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        XLogoArtwork.path(in: rect)
    }
}

enum XLogoArtwork {
    private static let canvasSize: CGFloat = 24

    static func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / canvasSize
        let xOffset = rect.minX + (rect.width - canvasSize * scale) / 2
        let yOffset = rect.minY + (rect.height - canvasSize * scale) / 2

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: xOffset + x * scale,
                y: yOffset + (canvasSize - y) * scale
            )
        }

        var path = Path()
        path.move(to: point(18.244, 2.25))
        path.addLine(to: point(21.552, 2.25))
        path.addLine(to: point(14.325, 10.51))
        path.addLine(to: point(22.827, 21.75))
        path.addLine(to: point(16.17, 21.75))
        path.addLine(to: point(10.956, 14.933))
        path.addLine(to: point(4.99, 21.75))
        path.addLine(to: point(1.68, 21.75))
        path.addLine(to: point(9.41, 12.915))
        path.addLine(to: point(1.254, 2.25))
        path.addLine(to: point(8.08, 2.25))
        path.addLine(to: point(12.793, 8.481))
        path.closeSubpath()

        path.move(to: point(17.083, 19.77))
        path.addLine(to: point(18.916, 19.77))
        path.addLine(to: point(7.084, 4.126))
        path.addLine(to: point(5.117, 4.126))
        path.closeSubpath()
        return path
    }

    static func image(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.labelColor.setFill()
        let path = NSBezierPath(XLogoShape().path(in: CGRect(
            origin: .zero,
            size: CGSize(width: size, height: size)
        )).cgPath)
        path.windingRule = .evenOdd
        path.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

private extension NSBezierPath {
    convenience init(_ cgPath: CGPath) {
        self.init()
        cgPath.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                move(to: element.points[0])
            case .addLineToPoint:
                line(to: element.points[0])
            case .addQuadCurveToPoint:
                let current = currentPoint
                let control = element.points[0]
                let end = element.points[1]
                curve(
                    to: end,
                    controlPoint1: CGPoint(
                        x: current.x + 2 / 3 * (control.x - current.x),
                        y: current.y + 2 / 3 * (control.y - current.y)
                    ),
                    controlPoint2: CGPoint(
                        x: end.x + 2 / 3 * (control.x - end.x),
                        y: end.y + 2 / 3 * (control.y - end.y)
                    )
                )
            case .addCurveToPoint:
                curve(
                    to: element.points[2],
                    controlPoint1: element.points[0],
                    controlPoint2: element.points[1]
                )
            case .closeSubpath:
                close()
            @unknown default:
                break
            }
        }
    }
}
