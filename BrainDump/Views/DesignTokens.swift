import SwiftUI

enum DesignTokens {
    static let primaryPurple = Color(red: 44 / 255, green: 42 / 255, blue: 69 / 255)
    static let contentBackground = Color(red: 33 / 255, green: 34 / 255, blue: 40 / 255)
    static let contentSurface = Color(red: 40 / 255, green: 41 / 255, blue: 48 / 255)
}

struct TopLeadingRoundedRectangle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let corner = min(radius, min(rect.width, rect.height) / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + corner, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}
