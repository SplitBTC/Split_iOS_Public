//  RampCode.swift
//  Split Rewards
//
//  Created by TeeVee on 1/22/26.
//
import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct RampPriceCard: View {
    let priceText: String
    let onRefreshPrice: () -> Void

    @State private var chartPoints: [BitcoinPricePoint] = []
    @State private var isLoadingChart = false
    @State private var chartErrorText: String?
    @State private var selectedChartPoint: BitcoinPricePoint?
    @State private var selectedRange: BitcoinChartRange = .day

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            priceHeader
                .padding(.trailing, 34)

            chartContent

            rangePicker
                .padding(.top, 2)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.02),
                            Color.black.opacity(0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        .overlay(alignment: .topTrailing) {
            refreshCornerButton
                .padding(.top, 12)
                .padding(.trailing, 12)
        }
        .task(id: selectedRange) {
            await loadChart()
        }
    }

    private var displayedPoint: BitcoinPricePoint? {
        selectedChartPoint ?? chartPoints.last
    }

    private var currentPriceText: String {
        guard let point = displayedPoint else { return priceText }
        return formatUSD(point.priceUSD)
    }

    private var currentPriceSubtitleText: String? {
        guard let point = displayedPoint else { return nil }

        let df = DateFormatter()
        df.locale = .current
        df.timeZone = .current

        if selectedChartPoint != nil {
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: point.date)
        }

        switch selectedRange {
        case .day:
            df.dateStyle = .none
            df.timeStyle = .short
        case .month, .year, .yearToDate:
            df.dateStyle = .medium
            df.timeStyle = .none
        }

        return "As of \(df.string(from: point.date))"
    }

    private var percentChangeText: String {
        guard
            let first = chartPoints.first?.priceUSD,
            let shown = displayedPoint?.priceUSD,
            first != 0
        else { return "—" }

        let pct = (shown - first) / first * 100.0
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(formatPercent(pct))"
    }

    private var percentChangeColor: Color {
        guard
            let first = chartPoints.first?.priceUSD,
            let shown = displayedPoint?.priceUSD
        else { return .white.opacity(0.75) }

        if shown > first { return .green }
        if shown < first { return .red }
        return .white.opacity(0.75)
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(currentPriceText)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()

            HStack(spacing: 10) {
                Text(percentChangeText)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(percentChangeColor)
                    .monospacedDigit()

                if let subtitle = currentPriceSubtitleText {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.70))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        if isLoadingChart {
            chartPlaceholder {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)

                    Text("Loading chart...")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        } else if let chartErrorText {
            chartPlaceholder {
                VStack(spacing: 8) {
                    Text("Couldn't load chart")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(chartErrorText)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 14)
            }
        } else if chartPoints.isEmpty {
            chartPlaceholder {
                Text("No data.")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.75))
            }
        } else {
            BitcoinPriceLineChart(
                points: chartPoints,
                selectedPoint: $selectedChartPoint,
                height: 260
            )
        }
    }

    private func chartPlaceholder<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .background(
                LinearGradient(
                    colors: [Color.splitSurface, Color.splitIndigo.opacity(0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var refreshCornerButton: some View {
        Button {
            onRefreshPrice()
            Task { await loadChart() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoadingChart)
        .accessibilityLabel("Refresh Bitcoin price")
    }

    private var rangePicker: some View {
        HStack(spacing: 10) {
            rangeButton(.day, title: "Day")
            rangeButton(.month, title: "Month")
            rangeButton(.year, title: "Year")
            rangeButton(.yearToDate, title: "YTD")
        }
        .frame(maxWidth: .infinity)
    }

    private func rangeButton(_ range: BitcoinChartRange, title: String) -> some View {
        let isSelected = (range == selectedRange)

        return Button {
            selectedRange = range
        } label: {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: [Color.splitBerry, Color.splitBrandPink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            Color.splitSurfaceRaised
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.16 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func formatPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)) + "%"
    }

    @MainActor
    private func loadChart() async {
        isLoadingChart = true
        chartErrorText = nil
        selectedChartPoint = nil

        do {
            chartPoints = try await fetchBitcoinPriceSeriesUSD(range: selectedRange)
            isLoadingChart = false
        } catch {
            chartErrorText = error.localizedDescription
            chartPoints = []
            isLoadingChart = false
        }
    }
}

@available(iOS 16.0, *)
private struct BitcoinPriceLineChart: View {
    let points: [BitcoinPricePoint]
    @Binding var selectedPoint: BitcoinPricePoint?
    let height: CGFloat

    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink
    private let indigo = Color.splitIndigo
    private let surface = Color.splitSurface

    var body: some View {
        let prices = points.map { $0.priceUSD }
        let minPrice = prices.min() ?? 0
        let maxPrice = prices.max() ?? 0
        let rawRange = maxPrice - minPrice

        let padding = rawRange > 0 ? (rawRange * 0.10) : max(1.0, maxPrice * 0.002)
        let lowerBound = minPrice - padding
        let upperBound = maxPrice + padding

        return Chart {
            ForEach(points) { p in
                LineMark(
                    x: .value("Time", p.date),
                    y: .value("Price", p.priceUSD)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [blue, pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            if let sp = selectedPoint {
                RuleMark(x: .value("Selected", sp.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.white.opacity(0.35))

                PointMark(
                    x: .value("Selected", sp.date),
                    y: .value("Price", sp.priceUSD)
                )
                .symbolSize(55)
                .foregroundStyle(.white)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: lowerBound...upperBound)
        .frame(height: height)
        .background(
            LinearGradient(
                colors: [surface, indigo.opacity(0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotArea = geo[plotFrame]
                                let xInPlot = value.location.x - plotArea.origin.x
                                guard xInPlot >= 0, xInPlot <= plotArea.size.width else { return }

                                if let date: Date = proxy.value(atX: xInPlot) {
                                    selectedPoint = nearestPoint(to: date)
                                }
                            }
                            .onEnded { _ in
                                selectedPoint = nil
                            }
                    )
            }
        }
    }

    private func nearestPoint(to date: Date) -> BitcoinPricePoint? {
        guard !points.isEmpty else { return nil }
        return points.min { a, b in
            abs(a.date.timeIntervalSince(date)) < abs(b.date.timeIntervalSince(date))
        }
    }
}
