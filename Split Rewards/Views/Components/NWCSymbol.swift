//
//  NWCSymbol.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import SwiftUI

struct NWCSymbol: View {
    var accentColor: Color = Color(red: 1.0, green: 0.66, blue: 0.10)
    var secondaryColor: Color = Color(red: 0.52, green: 0.45, blue: 1.0)
    var foregroundColor: Color = .black

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let cornerRadius = size * 0.085

            ZStack {
                Circle()
                    .fill(Color.black)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(secondaryColor)
                    .frame(width: size * 0.34, height: size * 0.58)
                    .rotationEffect(.degrees(-35))
                    .offset(x: size * 0.20, y: -size * 0.16)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(1.0),
                                Color(red: 1.0, green: 0.55, blue: 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.55, height: size * 0.55)
                    .rotationEffect(.degrees(-45))

                PlugSilhouette()
                    .fill(foregroundColor)
                    .frame(width: size * 0.39, height: size * 0.38)
                    .rotationEffect(.degrees(-45))
                    .offset(x: -size * 0.01, y: size * 0.07)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct PlugSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY

        var path = Path()

        path.move(to: CGPoint(x: x + w * 0.08, y: y + h * 0.36))
        path.addLine(to: CGPoint(x: x + w * 0.24, y: y + h * 0.36))
        path.addLine(to: CGPoint(x: x + w * 0.24, y: y + h * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.31, y: y + h * 0.18),
            control: CGPoint(x: x + w * 0.275, y: y + h * 0.11)
        )
        path.addLine(to: CGPoint(x: x + w * 0.31, y: y + h * 0.36))
        path.addLine(to: CGPoint(x: x + w * 0.42, y: y + h * 0.36))
        path.addLine(to: CGPoint(x: x + w * 0.42, y: y + h * 0.11))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.11),
            control: CGPoint(x: x + w * 0.46, y: y + h * 0.04)
        )
        path.addLine(to: CGPoint(x: x + w * 0.50, y: y + h * 0.36))
        path.addLine(to: CGPoint(x: x + w * 0.62, y: y + h * 0.36))
        path.addLine(to: CGPoint(x: x + w * 0.62, y: y + h * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.70, y: y + h * 0.18),
            control: CGPoint(x: x + w * 0.66, y: y + h * 0.11)
        )
        path.addLine(to: CGPoint(x: x + w * 0.70, y: y + h * 0.38))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.90, y: y + h * 0.59),
            control: CGPoint(x: x + w * 0.84, y: y + h * 0.42)
        )
        path.addLine(to: CGPoint(x: x + w * 0.90, y: y + h * 0.72))
        path.addLine(to: CGPoint(x: x + w * 0.72, y: y + h * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.39, y: y + h * 0.92),
            control: CGPoint(x: x + w * 0.63, y: y + h * 0.92)
        )
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.12, y: y + h * 0.62),
            control: CGPoint(x: x + w * 0.18, y: y + h * 0.90)
        )
        path.addLine(to: CGPoint(x: x + w * 0.08, y: y + h * 0.62))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.08, y: y + h * 0.36),
            control: CGPoint(x: x - w * 0.02, y: y + h * 0.49)
        )
        path.closeSubpath()

        return path
    }
}
