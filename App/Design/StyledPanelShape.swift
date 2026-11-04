// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Silhouette des panneaux et de leurs aperçus. L'inset garde les bordures à l'intérieur de la forme.
/// Les différences sont purement visuelles : disposition, zones de toucher et PDF restent indépendants.
struct StyledPanelShape: InsettableShape {
    var radius: CGFloat
    var kind: AppStyle.PanelShape
    private var insetAmount: CGFloat = 0

    init(radius: CGFloat, kind: AppStyle.PanelShape) {
        self.radius = radius
        self.kind = kind
    }

    func inset(by amount: CGFloat) -> StyledPanelShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard box.width > 0, box.height > 0 else { return Path() }
        let limit = min(box.width, box.height) / 2
        let r = min(max(0, radius - insetAmount), limit)
        switch kind {
        case .rounded:
            return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: box)
        case .chamfered:
            let cut = min(max(0, 12 - insetAmount), limit)
            var p = Path()
            p.move(to: CGPoint(x: box.minX + cut, y: box.minY))
            p.addLine(to: CGPoint(x: box.maxX - cut, y: box.minY))
            p.addLine(to: CGPoint(x: box.maxX, y: box.minY + cut))
            p.addLine(to: CGPoint(x: box.maxX, y: box.maxY - cut))
            p.addLine(to: CGPoint(x: box.maxX - cut, y: box.maxY))
            p.addLine(to: CGPoint(x: box.minX + cut, y: box.maxY))
            p.addLine(to: CGPoint(x: box.minX, y: box.maxY - cut))
            p.addLine(to: CGPoint(x: box.minX, y: box.minY + cut))
            p.closeSubpath()
            return p
        case .organic:
            let wide = min(r * 1.4, limit), narrow = r * 0.4
            var p = Path()
            p.move(to: CGPoint(x: box.minX + wide, y: box.minY))
            p.addLine(to: CGPoint(x: box.maxX - narrow, y: box.minY))
            p.addQuadCurve(to: CGPoint(x: box.maxX, y: box.minY + narrow), control: CGPoint(x: box.maxX, y: box.minY))
            p.addLine(to: CGPoint(x: box.maxX, y: box.maxY - wide))
            p.addQuadCurve(to: CGPoint(x: box.maxX - wide, y: box.maxY), control: CGPoint(x: box.maxX, y: box.maxY))
            p.addLine(to: CGPoint(x: box.minX + narrow, y: box.maxY))
            p.addQuadCurve(to: CGPoint(x: box.minX, y: box.maxY - narrow), control: CGPoint(x: box.minX, y: box.maxY))
            p.addLine(to: CGPoint(x: box.minX, y: box.minY + wide))
            p.addQuadCurve(to: CGPoint(x: box.minX + wide, y: box.minY), control: CGPoint(x: box.minX, y: box.minY))
            p.closeSubpath()
            return p
        }
    }
}
