import SwiftUI

struct ApexSlashPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width / 3
        for index in 0..<4 {
            let x = CGFloat(index) * width - width
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + width, y: rect.minY))
            path.addLine(to: CGPoint(x: x + width * 1.65, y: rect.minY))
            path.addLine(to: CGPoint(x: x + width * 0.65, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

