import SwiftUI

struct CashAppAmountSheet: View {
    enum AmountUnit: String, CaseIterable {
        case usd = "USD"
        case sats = "Sats"
    }

    private struct QuickAmountOption: Identifiable {
        let id: String
        let label: String
        let rawValue: String
    }

    let btcUsdRate: Double?
    let isStarting: Bool
    let onStart: (_ amountSats: UInt64) -> Void
    let onCancel: () -> Void

    @State private var amountUnit: AmountUnit = .usd
    @State private var amountText: String = ""
    @FocusState private var amountFieldFocused: Bool

    private let appBlack = Color.splitAppBlack
    private let cardSurface = Color.splitCardSurface
    private let chipSurface = Color.white.opacity(0.06)
    private let chipBorder = Color.white.opacity(0.10)
    private let hairline = Color.white.opacity(0.08)
    private let accent = Color.splitBrandBlue

    private var amountSats: UInt64? {
        parseAmountSats(for: amountUnit, inputText: amountText)
    }

    private var canContinue: Bool {
        !isStarting && amountSats != nil
    }

    private var inputPlaceholder: String {
        switch amountUnit {
        case .usd:
            return "0.00"
        case .sats:
            return "1000"
        }
    }

    private var conversionText: String? {
        guard let amountSats else { return nil }

        switch amountUnit {
        case .usd:
            return formatSatsDisplay(amountSats)
        case .sats:
            guard let rate = btcUsdRate, rate > 0 else { return nil }
            let usdAmount = (Double(amountSats) / 100_000_000.0) * rate
            return formatUSDDisplay(usdAmount)
        }
    }

    private var quickAmounts: [QuickAmountOption] {
        switch amountUnit {
        case .usd:
            return [
                QuickAmountOption(id: "usd-25", label: "$25", rawValue: "25"),
                QuickAmountOption(id: "usd-50", label: "$50", rawValue: "50"),
                QuickAmountOption(id: "usd-100", label: "$100", rawValue: "100"),
                QuickAmountOption(id: "usd-250", label: "$250", rawValue: "250")
            ]
        case .sats:
            return [
                QuickAmountOption(id: "sats-10000", label: "10k sats", rawValue: "10000"),
                QuickAmountOption(id: "sats-25000", label: "25k sats", rawValue: "25000"),
                QuickAmountOption(id: "sats-50000", label: "50k sats", rawValue: "50000"),
                QuickAmountOption(id: "sats-100000", label: "100k sats", rawValue: "100000")
            ]
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBlack
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        Text("Purchase Amount")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Spacer()

                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.82))
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    amountInputCard
                    unitSelector
                    quickAmountChips

                    if let conversionText {
                        Text(amountUnit == .usd ? "Approx. \(conversionText)" : "Approx. \(conversionText)")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.62))
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 20)
                .padding(.top, 26)
                .padding(.bottom, 132)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottom) {
                bottomBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .contentShape(Rectangle())
            .onTapGesture {
                amountFieldFocused = false
            }
        }
        .onChange(of: amountUnit) { oldUnit, newUnit in
            syncDisplayForSelectedUnit(from: oldUnit, to: newUnit)
        }
        .onChange(of: amountText) { _, newValue in
            let sanitized = sanitizeAmountText(newValue, for: amountUnit)
            if sanitized != newValue {
                amountText = sanitized
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    amountFieldFocused = false
                }
            }
        }
    }

    private var amountInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Purchase amount")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.62))

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if amountUnit == .usd {
                    Text("$")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                }

                ZStack(alignment: .leading) {
                    if amountText.isEmpty {
                        Text(inputPlaceholder)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.20))
                    }

                    TextField("", text: $amountText)
                        .keyboardType(amountUnit == .usd ? .decimalPad : .numberPad)
                        .focused($amountFieldFocused)
                        .foregroundColor(.white)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                }

                if amountUnit == .sats {
                    Text("sats")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.72))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            amountFieldFocused = true
        }
    }

    private var unitSelector: some View {
        HStack(spacing: 10) {
            ForEach(AmountUnit.allCases, id: \.self) { unit in
                Button {
                    amountUnit = unit
                } label: {
                    Text(unit.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(amountUnit == unit ? .black : .white.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(amountUnit == unit ? Color.white : chipSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(amountUnit == unit ? Color.clear : chipBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quickAmountChips: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            ForEach(quickAmounts) { option in
                Button {
                    amountText = option.rawValue
                    amountFieldFocused = false
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(chipSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(chipBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button {
                guard let amountSats else { return }
                onStart(amountSats)
            } label: {
                HStack {
                    Spacer()
                    if isStarting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue to Cash App")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(canContinue ? accent : Color.white.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            appBlack
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
        )
    }

    private func syncDisplayForSelectedUnit(from oldUnit: AmountUnit, to newUnit: AmountUnit) {
        guard oldUnit != newUnit else { return }

        guard let sats = parseAmountSats(for: oldUnit, inputText: amountText) else {
            amountText = ""
            return
        }

        switch newUnit {
        case .usd:
            guard let rate = btcUsdRate, rate > 0 else {
                amountText = ""
                return
            }

            let usdAmount = (Double(sats) / 100_000_000.0) * rate
            amountText = formatUSDInput(usdAmount)
        case .sats:
            amountText = "\(sats)"
        }
    }

    private func sanitizeAmountText(_ value: String, for unit: AmountUnit) -> String {
        if unit == .sats {
            let digits = value.filter { $0.isWholeNumber }
            return String(digits.drop(while: { $0 == "0" }))
        }

        let maxFractionDigits: Int

        switch unit {
        case .usd:
            maxFractionDigits = 2
        case .sats:
            maxFractionDigits = 0
        }

        var result = ""
        var hasDecimalSeparator = false
        var decimalCount = 0

        for character in value {
            if character.isWholeNumber {
                if hasDecimalSeparator {
                    guard decimalCount < maxFractionDigits else { continue }
                    decimalCount += 1
                }
                result.append(character)
            } else if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(character)
            }
        }

        if result == "." {
            return "0."
        }

        return result
    }

    private func parseAmountSats(for unit: AmountUnit, inputText: String) -> UInt64? {
        let cleaned = inputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        if unit == .sats {
            guard let sats = UInt64(cleaned), sats > 0 else { return nil }
            return sats
        }

        guard let decimalValue = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              isPositive(decimalValue) else {
            return nil
        }

        switch unit {
        case .usd:
            guard let rate = btcUsdRate, rate > 0 else { return nil }
            let satsDecimal = (decimalValue / Decimal(rate)) * Decimal(100_000_000)
            return roundedUInt64(from: satsDecimal)
        case .sats:
            return nil
        }
    }

    private func roundedUInt64(from decimal: Decimal) -> UInt64? {
        let number = NSDecimalNumber(decimal: decimal)
        let rounded = number.rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )
        )

        guard rounded != .notANumber else { return nil }
        return UInt64(rounded.stringValue)
    }

    private func isPositive(_ value: Decimal) -> Bool {
        NSDecimalNumber(decimal: value).compare(NSDecimalNumber.zero) == .orderedDescending
    }

    private func formatUSDDisplay(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func formatUSDInput(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatSatsDisplay(_ value: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formatted) sats"
    }

}
