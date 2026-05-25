import SwiftUI

struct AddMerchantView: View {
    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let accentBlue = Color.splitBrandBlue
    private let accentPink = Color.splitBrandPink

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add a Merchant")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)

                        Text("You can add any bitcoin-accepting business to our rewards program.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    instructionCard

                    VStack(alignment: .leading, spacing: 14) {
                        stepRow(
                            number: "1",
                            title: "Make a normal bitcoin payment",
                            detail: "Pay the merchant with Split like a normal transaction."
                        )

                        stepRow(
                            number: "2",
                            title: "Open the transaction in Split",
                            detail: "Find that payment to the merchant in your Transactions list."
                        )

                        iconStepRow

                        stepRow(
                            number: "4",
                            title: "Submit the merchant form",
                            detail: "Enter the merchant name and address. The merchant does not need to participate. We’ll verify the business and add them as soon as possible."
                        )
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(cardSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(cardStroke, lineWidth: 1)
                            )
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Good to know")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)

                        Text("This works for any business that accepts Bitcoin. Once approved, your spend with that merchant will start earning Bitcoin rewards.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(cardSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(cardStroke, lineWidth: 1)
                            )
                    )

                    Spacer(minLength: 18)
                }
                .padding(16)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentBlue, accentPink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "storefront.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white, .black)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text("See a business missing from rewards?")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    Text("You can submit it right from the payment.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.70))
                }
            }

            Text("After you pay, open the transaction and tap the merchant button below to send us the business details.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text("Tap this icon")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.82))

                Image(systemName: "storefront.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white, .black)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
        )
    }

    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(accentBlue)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)

                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var iconStepRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("3")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(accentBlue)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text("Tap the merchant icon")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)

                Text("Inside the transaction detail, tap the merchant button to open the submission form.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "storefront.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white, .black)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
        }
    }
}

#Preview {
    NavigationStack {
        AddMerchantView()
    }
}
