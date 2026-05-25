//
//  ToastView.swift
//  Split Rewards
//
//  A global payment result overlay that listens to ToastManager
//  and presents a centered card above the active screen.
//

import SwiftUI
import CoreHaptics
import UIKit

struct ToastView: View {
    @EnvironmentObject private var toastManager: ToastManager

    var body: some View {
        GeometryReader { _ in
            if let toast = toastManager.activeToast {
                ZStack {
                    Color.black.opacity(toast.kind == .paymentPending ? 0.08 : 0.14)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    ToastCardView(toast: toast) {
                        toastManager.hide()
                    }
                    .id(toast.id)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(cardTransition)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard toast.isTapToDismissEnabled else { return }
                    toastManager.hide()
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(toastManager.activeToast?.blocksInteraction ?? false)
        .animation(.spring(response: 0.38, dampingFraction: 0.84), value: toastManager.activeToast)
    }

    private var cardTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92)
                .combined(with: .opacity),
            removal: .scale(scale: 0.96)
                .combined(with: .opacity)
        )
    }
}

private struct ToastCardView: View {
    let toast: AppToast
    let onDismiss: () -> Void

    @State private var cardScale: CGFloat = 0.9
    @State private var cardOpacity: Double = 0.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var burstScale: CGFloat = 0.92
    @State private var burstOpacity: Double = 0.0

    private var style: ToastStyle {
        ToastStyle.forToast(toast)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white)

            if !style.showsPendingSparkHero {
                ToastBurstBackground(
                    primary: style.burstPrimary,
                    secondary: style.burstSecondary,
                    glow: style.burstGlow,
                    isElectric: style.isElectric
                )
                    .scaleEffect(burstScale)
                    .opacity(burstOpacity)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))

                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white,
                                Color.white.opacity(0.99),
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.78),
                                Color.white.opacity(0.16),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 158
                        )
                    )
            }

            Group {
                if style.showsPendingSparkHero {
                    VStack {
                        Spacer(minLength: 0)
                        PendingSparkHeroView(style: style)
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(spacing: 18) {
                        Spacer(minLength: style.showsBitcoinHero ? 14 : 0)

                        ToastHeroSymbolView(style: style)

                        VStack(spacing: 8) {
                            Text(style.displayTitle ?? toast.title)
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(Color.black.opacity(0.86))
                                .multilineTextAlignment(.center)

                            if let subtitle = toast.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color.black.opacity(0.64))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                            }
                        }

                        if let eyebrow = style.eyebrow {
                            Text(eyebrow)
                                .font(.system(size: 12, weight: .semibold))
                                .kerning(1.2)
                                .foregroundColor(style.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(style.accent.opacity(0.12))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(style.accent.opacity(0.22), lineWidth: 1)
                                )
                        }

                        Spacer(minLength: style.showsBitcoinHero ? 12 : 0)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 292)
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: style.burstGlow.opacity(0.30), radius: 30, x: 0, y: 22)
        .scaleEffect(cardScale * pulseScale)
        .opacity(cardOpacity)
        .onTapGesture {
            guard toast.isTapToDismissEnabled else { return }
            onDismiss()
        }
        .onAppear {
            ToastHaptics.play(for: toast)
            animateCard()
        }
    }

    private func animateCard() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            cardScale = 1.0
            cardOpacity = 1.0
            burstScale = 1.0
            burstOpacity = 1.0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                pulseScale = 1.025
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.easeOut(duration: 0.22)) {
                pulseScale = 1.0
            }
        }
    }
}

private struct PendingSparkHeroView: View {
    let style: ToastStyle

    @State private var tokenScale: CGFloat = 0.98

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(style.heroGradientStart.opacity(0.08))
                    .frame(width: 138, height: 138)

                Circle()
                    .stroke(style.heroGradientStart.opacity(0.10), lineWidth: 8)
                    .frame(width: 130, height: 130)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                style.heroGradientStart,
                                style.heroGradientEnd
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.06),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 72
                        )
                    )
                    .frame(width: 110, height: 110)

                Image(systemName: "bitcoinsign")
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(.white)
                    .offset(y: -1)
            }
            .scaleEffect(tokenScale)
            .shadow(color: style.heroGradientStart.opacity(0.12), radius: 10, x: 0, y: 6)
            .shadow(color: style.heroGradientEnd.opacity(0.10), radius: 16, x: 0, y: 8)

            PendingSparkDotsView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                tokenScale = 1.02
            }
        }
    }
}

private struct PendingSparkDotsView: View {
    private let dotCount = 4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.18)) { context in
            let activeIndex = Int(context.date.timeIntervalSinceReferenceDate / 0.18) % dotCount

            HStack(spacing: 12) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(Color.splitBrandBlue.opacity(opacity(for: index, activeIndex: activeIndex)))
                        .frame(width: 9, height: 9)
                        .scaleEffect(scale(for: index, activeIndex: activeIndex))
                        .animation(.easeInOut(duration: 0.16), value: activeIndex)
                }
            }
        }
    }

    private func opacity(for index: Int, activeIndex: Int) -> Double {
        if index == activeIndex {
            return 1.0
        }
        if index == previousIndex(for: activeIndex) {
            return 0.42
        }
        return 0.16
    }

    private func scale(for index: Int, activeIndex: Int) -> CGFloat {
        if index == activeIndex {
            return 1.18
        }
        if index == previousIndex(for: activeIndex) {
            return 0.98
        }
        return 0.82
    }

    private func previousIndex(for activeIndex: Int) -> Int {
        (activeIndex - 1 + dotCount) % dotCount
    }
}

private struct ToastBurstBackground: View {
    let primary: Color
    let secondary: Color
    let glow: Color
    let isElectric: Bool

    private let rays: [ToastBurstRaySpec] = [
        .init(angleDegrees: -80, start: 0.20, end: 0.96, startWidth: 0.009, endWidth: 0.182, opacity: 0.98),
        .init(angleDegrees: -49, start: 0.26, end: 0.88, startWidth: 0.007, endWidth: 0.104, opacity: 0.78),
        .init(angleDegrees: -20, start: 0.23, end: 0.97, startWidth: 0.007, endWidth: 0.146, opacity: 0.92),
        .init(angleDegrees: 9, start: 0.30, end: 1.00, startWidth: 0.006, endWidth: 0.082, opacity: 0.68),
        .init(angleDegrees: 34, start: 0.24, end: 0.95, startWidth: 0.008, endWidth: 0.138, opacity: 0.92),
        .init(angleDegrees: 67, start: 0.20, end: 0.97, startWidth: 0.009, endWidth: 0.176, opacity: 0.96),
        .init(angleDegrees: 121, start: 0.22, end: 0.95, startWidth: 0.008, endWidth: 0.146, opacity: 0.92),
        .init(angleDegrees: 170, start: 0.28, end: 0.90, startWidth: 0.006, endWidth: 0.084, opacity: 0.68),
        .init(angleDegrees: 207, start: 0.23, end: 0.98, startWidth: 0.009, endWidth: 0.156, opacity: 0.94),
        .init(angleDegrees: 246, start: 0.21, end: 0.98, startWidth: 0.009, endWidth: 0.184, opacity: 0.97),
        .init(angleDegrees: 307, start: 0.23, end: 0.93, startWidth: 0.008, endWidth: 0.126, opacity: 0.88),
        .init(angleDegrees: 338, start: 0.29, end: 0.95, startWidth: 0.006, endWidth: 0.088, opacity: 0.70)
    ]

    private let electricStreaks: [ElectricStreakSpec] = [
        .init(width: 0.62, thickness: 0.085, rotationDegrees: -28, xOffset: 0.19, yOffset: -0.20, opacity: 0.94),
        .init(width: 0.56, thickness: 0.074, rotationDegrees: 26, xOffset: -0.24, yOffset: 0.20, opacity: 0.90),
        .init(width: 0.38, thickness: 0.046, rotationDegrees: -62, xOffset: 0.04, yOffset: 0.24, opacity: 0.78)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white

                Circle()
                    .fill(secondary.opacity(0.26))
                    .frame(width: proxy.size.width * 0.74)
                    .blur(radius: 62)
                    .offset(x: -proxy.size.width * 0.22, y: proxy.size.height * 0.18)

                Circle()
                    .fill(primary.opacity(0.20))
                    .frame(width: proxy.size.width * 0.80)
                    .blur(radius: 70)
                    .offset(x: proxy.size.width * 0.24, y: -proxy.size.height * 0.22)

                Circle()
                    .fill(glow.opacity(0.24))
                    .frame(width: proxy.size.width * 0.98)
                    .blur(radius: 84)

                if isElectric {
                    ForEach(Array(electricStreaks.enumerated()), id: \.offset) { _, spec in
                        ElectricStreak(
                            spec: spec,
                            primary: primary,
                            secondary: secondary
                        )
                        .frame(
                            width: proxy.size.width * spec.width,
                            height: proxy.size.height * spec.thickness
                        )
                        .rotationEffect(.degrees(spec.rotationDegrees))
                        .offset(
                            x: proxy.size.width * spec.xOffset,
                            y: proxy.size.height * spec.yOffset
                        )
                        .opacity(spec.opacity)
                    }
                }

                ForEach(Array(rays.enumerated()), id: \.offset) { index, spec in
                    ToastBurstRayShape(spec: spec)
                        .fill(rayGradient(for: spec))
                        .opacity(spec.opacity)
                        .blendMode(.normal)

                    ToastBurstRayShape(spec: highlightSpec(for: spec))
                        .fill(highlightGradient(for: spec))
                        .opacity(min(spec.opacity + 0.08, 1.0))
                        .blendMode(.normal)
                }

                LinearGradient(
                    colors: [
                        secondary.opacity(0.14),
                        Color.clear,
                        primary.opacity(0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color.white,
                        Color.white,
                        Color.white.opacity(0.94),
                        Color.white.opacity(0.56),
                        Color.white.opacity(0.04),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(proxy.size.width, proxy.size.height) * 0.42
                )
            }
        }
    }

    private func rayGradient(for spec: ToastBurstRaySpec) -> LinearGradient {
        let startPoint = unitPoint(forDegrees: spec.angleDegrees)
        let endPoint = unitPoint(forDegrees: spec.angleDegrees + 180)
        return LinearGradient(
            stops: [
                .init(color: secondary.opacity(1.0), location: 0.0),
                .init(color: primary.opacity(1.0), location: 0.34),
                .init(color: primary.opacity(0.72), location: 0.74),
                .init(color: primary.opacity(0.05), location: 1.0)
            ],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    private func highlightGradient(for spec: ToastBurstRaySpec) -> LinearGradient {
        let startPoint = unitPoint(forDegrees: spec.angleDegrees)
        let endPoint = unitPoint(forDegrees: spec.angleDegrees + 180)
        return LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.98), location: 0.0),
                .init(color: secondary.opacity(0.98), location: 0.42),
                .init(color: primary.opacity(0.30), location: 0.84),
                .init(color: primary.opacity(0.0), location: 1.0)
            ],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    private func highlightSpec(for spec: ToastBurstRaySpec) -> ToastBurstRaySpec {
        ToastBurstRaySpec(
            angleDegrees: spec.angleDegrees,
            start: spec.start,
            end: spec.end,
            startWidth: spec.startWidth * 0.54,
            endWidth: spec.endWidth * 0.40,
            opacity: min(spec.opacity + 0.08, 1.0)
        )
    }

    private func unitPoint(forDegrees degrees: Double) -> UnitPoint {
        let radians = degrees * .pi / 180
        return UnitPoint(
            x: 0.5 + cos(radians) * 0.5,
            y: 0.5 + sin(radians) * 0.5
        )
    }
}

private struct ToastBurstRaySpec {
    let angleDegrees: Double
    let start: CGFloat
    let end: CGFloat
    let startWidth: CGFloat
    let endWidth: CGFloat
    let opacity: Double
}

private struct ToastBurstRayShape: Shape {
    let spec: ToastBurstRaySpec

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxDimension = max(rect.width, rect.height)
        let theta = spec.angleDegrees * .pi / 180

        let direction = CGVector(dx: cos(theta), dy: sin(theta))
        let perpendicular = CGVector(dx: -direction.dy, dy: direction.dx)

        let startRadius = maxDimension * spec.start
        let endRadius = maxDimension * spec.end
        let startWidth = maxDimension * spec.startWidth
        let endWidth = maxDimension * spec.endWidth

        let startCenter = CGPoint(
            x: center.x + direction.dx * startRadius,
            y: center.y + direction.dy * startRadius
        )
        let endCenter = CGPoint(
            x: center.x + direction.dx * endRadius,
            y: center.y + direction.dy * endRadius
        )

        let p1 = CGPoint(
            x: startCenter.x + perpendicular.dx * (startWidth / 2),
            y: startCenter.y + perpendicular.dy * (startWidth / 2)
        )
        let p2 = CGPoint(
            x: endCenter.x + perpendicular.dx * (endWidth / 2),
            y: endCenter.y + perpendicular.dy * (endWidth / 2)
        )
        let p3 = CGPoint(
            x: endCenter.x - perpendicular.dx * (endWidth / 2),
            y: endCenter.y - perpendicular.dy * (endWidth / 2)
        )
        let p4 = CGPoint(
            x: startCenter.x - perpendicular.dx * (startWidth / 2),
            y: startCenter.y - perpendicular.dy * (startWidth / 2)
        )

        var path = Path()
        path.move(to: p1)
        path.addLine(to: p2)
        path.addLine(to: p3)
        path.addLine(to: p4)
        path.closeSubpath()
        return path
    }
}

private struct ElectricStreakSpec {
    let width: CGFloat
    let thickness: CGFloat
    let rotationDegrees: Double
    let xOffset: CGFloat
    let yOffset: CGFloat
    let opacity: Double
}

private struct ElectricStreak: View {
    let spec: ElectricStreakSpec
    let primary: Color
    let secondary: Color

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            secondary.opacity(1.0),
                            primary.opacity(0.96)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .blur(radius: 0.8)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            secondary.opacity(0.96),
                            Color.white.opacity(0.82)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 6)
                .blur(radius: 0.3)
        }
        .shadow(color: secondary.opacity(0.50), radius: 12, x: 0, y: 0)
        .shadow(color: primary.opacity(0.34), radius: 22, x: 0, y: 0)
    }
}

private struct ToastStyle {
    let accent: Color
    let burstPrimary: Color
    let burstSecondary: Color
    let burstGlow: Color
    let heroGradientStart: Color
    let heroGradientEnd: Color
    let symbolName: String
    let eyebrow: String?
    let showsBitcoinHero: Bool
    let showsPendingSparkHero: Bool
    let isElectric: Bool
    let displayTitle: String?

    static func forToast(_ toast: AppToast) -> ToastStyle {
        switch toast.kind {
        case .paymentPending:
            return ToastStyle(
                accent: .splitBrandBlue,
                burstPrimary: .splitBrandBlue,
                burstSecondary: .splitBrandPink,
                burstGlow: Color(red: 27 / 255, green: 53 / 255, blue: 126 / 255),
                heroGradientStart: .splitBrandBlue,
                heroGradientEnd: .splitBrandPink,
                symbolName: "bitcoinsign",
                eyebrow: nil,
                showsBitcoinHero: false,
                showsPendingSparkHero: true,
                isElectric: true,
                displayTitle: nil
            )

        case .paymentSuccess:
            switch toast.direction {
            case .received:
                return ToastStyle(
                    accent: .splitBrandBlue,
                    burstPrimary: .splitBrandBlue,
                    burstSecondary: .splitIndigo,
                    burstGlow: Color(red: 27 / 255, green: 53 / 255, blue: 126 / 255),
                    heroGradientStart: .splitBrandBlue,
                    heroGradientEnd: .splitBrandPink,
                    symbolName: "bitcoinsign",
                    eyebrow: nil,
                    showsBitcoinHero: true,
                    showsPendingSparkHero: false,
                    isElectric: true,
                    displayTitle: "Bitcoin received"
                )
            case .sent, .none:
                return ToastStyle(
                    accent: .splitBrandBlue,
                    burstPrimary: .splitBrandBlue,
                    burstSecondary: .splitIndigo,
                    burstGlow: Color(red: 27 / 255, green: 53 / 255, blue: 126 / 255),
                    heroGradientStart: .splitBrandBlue,
                    heroGradientEnd: .splitBrandPink,
                    symbolName: "bitcoinsign",
                    eyebrow: nil,
                    showsBitcoinHero: true,
                    showsPendingSparkHero: false,
                    isElectric: true,
                    displayTitle: "Bitcoin sent"
                )
            }

        case .paymentFailure:
            return ToastStyle(
                accent: Color(red: 0.88, green: 0.23, blue: 0.25),
                burstPrimary: Color(red: 0.82, green: 0.16, blue: 0.18),
                burstSecondary: Color(red: 1.0, green: 0.42, blue: 0.10),
                burstGlow: Color(red: 0.96, green: 0.28, blue: 0.16),
                heroGradientStart: Color(red: 0.88, green: 0.23, blue: 0.25),
                heroGradientEnd: Color(red: 1.0, green: 0.42, blue: 0.10),
                symbolName: "xmark",
                eyebrow: "FAILED",
                showsBitcoinHero: false,
                showsPendingSparkHero: false,
                isElectric: false,
                displayTitle: nil
            )

        case .info:
            return ToastStyle(
                accent: Color.black.opacity(0.72),
                burstPrimary: Color.black.opacity(0.58),
                burstSecondary: Color.black.opacity(0.42),
                burstGlow: Color.black.opacity(0.30),
                heroGradientStart: Color.black.opacity(0.70),
                heroGradientEnd: Color.black.opacity(0.44),
                symbolName: "info.circle.fill",
                eyebrow: "NOTICE",
                showsBitcoinHero: false,
                showsPendingSparkHero: false,
                isElectric: false,
                displayTitle: nil
            )

        case .error:
            return ToastStyle(
                accent: Color(red: 0.88, green: 0.23, blue: 0.25),
                burstPrimary: Color(red: 0.82, green: 0.16, blue: 0.18),
                burstSecondary: Color(red: 1.0, green: 0.42, blue: 0.10),
                burstGlow: Color(red: 0.96, green: 0.28, blue: 0.16),
                heroGradientStart: Color(red: 0.88, green: 0.23, blue: 0.25),
                heroGradientEnd: Color(red: 1.0, green: 0.42, blue: 0.10),
                symbolName: "exclamationmark.triangle.fill",
                eyebrow: "ERROR",
                showsBitcoinHero: false,
                showsPendingSparkHero: false,
                isElectric: false,
                displayTitle: nil
            )
        }
    }
}

private struct ToastHeroSymbolView: View {
    let style: ToastStyle

    var body: some View {
        if style.showsBitcoinHero {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                style.heroGradientStart,
                                style.heroGradientEnd
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .stroke(Color.white.opacity(0.42), lineWidth: 1.6)

                Image(systemName: style.symbolName)
                    .font(.system(size: 54, weight: .bold))
                    .foregroundColor(.white)
                    .offset(y: -1)
            }
            .frame(width: 112, height: 112)
            .shadow(color: style.heroGradientEnd.opacity(0.26), radius: 18, x: 0, y: 10)
            .shadow(color: style.heroGradientStart.opacity(0.18), radius: 30, x: 0, y: 16)
        } else {
            ZStack {
                Circle()
                    .fill(style.accent.opacity(0.14))
                    .frame(width: 72, height: 72)

                Circle()
                    .stroke(style.accent.opacity(0.30), lineWidth: 1.5)
                    .frame(width: 72, height: 72)

                Image(systemName: style.symbolName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(style.accent)
            }
        }
    }
}

private enum ToastHaptics {
    private static var activeEngine: CHHapticEngine?

    static func play(for toast: AppToast) {
        switch toast.kind {
        case .paymentPending:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.72)

        case .paymentSuccess:
            if toast.direction == .sent {
                playElectricSuccess()
            } else {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }

        case .paymentFailure, .error:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)

        case .info:
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.9)
        }
    }

    private static func playElectricSuccess() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
            return
        }

        do {
            let engine = try CHHapticEngine()
            activeEngine = engine
            try engine.start()

            let events = [
                transientEvent(intensity: 1.0, sharpness: 1.0, time: 0.00),
                continuousEvent(intensity: 0.28, sharpness: 0.82, time: 0.02, duration: 0.12),
                transientEvent(intensity: 0.62, sharpness: 0.94, time: 0.07),
                transientEvent(intensity: 0.82, sharpness: 1.0, time: 0.16)
            ]

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)

            engine.notifyWhenPlayersFinished { _ in
                Self.activeEngine = nil
                return .stopEngine
            }
        } catch {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }

    private static func transientEvent(
        intensity: Float,
        sharpness: Float,
        time: TimeInterval
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private static func continuousEvent(
        intensity: Float,
        sharpness: Float,
        time: TimeInterval,
        duration: TimeInterval
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }
}

struct ToastView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = ToastManager()
        manager.showPaymentSuccess(
            direction: .received,
            subtitle: "Your wallet balance has been updated."
        )

        return ZStack {
            Color.black.ignoresSafeArea()
            ToastView()
                .environmentObject(manager)
        }
    }
}
